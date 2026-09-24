import AppKit
import AuthenticationServices
import CryptoKit
import Security

@MainActor final class AsanaAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    struct Workspace: Codable { let gid: String; let name: String }
    struct AuthError: LocalizedError { let errorDescription: String?; init(_ text: String) { errorDescription = text } }
    private struct Tokens: Codable { let access_token: String; let refresh_token: String?; let expires_in: Int? }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    static let clientID = "1218835849042613"
    static let redirect = "https://yadot.netlify.app/.netlify/functions/asana-callback"
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    private var authSession: ASWebAuthenticationSession?
    private var cachedToken: String?
    private var expires = Date.distantPast
    private var epoch = 0
    var onChange: (() -> Void)?
    var busy = false
    var message = "Connect your account to load assigned tasks and parent briefs."
    var workspaces: [Workspace] = []
    var connected: Bool { UserDefaults.standard.bool(forKey: "asanaOAuthConnected") }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "today") + ".asana-oauth", kSecAttrAccount as String: "refresh-token"] }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AuthError("Could not start secure sign-in.") }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func callbackCode(_ url: URL, state: String) throws -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "today-asana", parts.host == "oauth",
              parts.queryItems?.filter({ $0.name == "state" }).count == 1,
              parts.queryItems?.first(where: { $0.name == "state" })?.value == state,
              parts.queryItems?.filter({ $0.name == "code" }).count == 1,
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty,
              !(parts.queryItems?.contains(where: { $0.name == "error" }) ?? false) else { throw AuthError("Sign-in response did not match this request. Please try again.") }
        return code
    }
    func connect() {
        guard !busy else { return }
        do {
            let state = try Self.random(), verifier = try Self.random()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            var url = URLComponents(string: "https://app.asana.com/-/oauth_authorize")!
            url.queryItems = [URLQueryItem(name: "client_id", value: Self.clientID), URLQueryItem(name: "redirect_uri", value: Self.redirect), URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "state", value: state), URLQueryItem(name: "scope", value: "tasks:read workspaces:read"), URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "code_challenge", value: challenge)]
            busy = true; message = "Finish connecting in the sign-in window."; onChange?()
            authSession = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "today-asana") { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    defer { self.busy = false; self.authSession = nil; self.onChange?() }
                    guard let result, error == nil else { self.message = "Sign-in cancelled. Your calendar connection is unchanged."; return }
                    do {
                        let code = try Self.callbackCode(result, state: state)
                        let token = try await self.exchange(["grant_type":"authorization_code", "code":code, "code_verifier":verifier])
                        guard let refresh = token.refresh_token else { throw AuthError("Asana did not grant renewable access.") }
                        try self.save(refresh)
                        self.cachedToken = token.access_token; self.expires = Date().addingTimeInterval(Double(token.expires_in ?? 3600) - 60)
                        UserDefaults.standard.set(true, forKey: "asanaOAuthConnected")
                        UserDefaults.standard.set(true, forKey: "asanaBriefsEnabled")
                        UserDefaults.standard.removeObject(forKey: "asanaDirectWorkspace")
                        try await self.loadWorkspaces()
                        self.message = "Connected. Choose the workspace for your assigned tasks."
                    } catch { self.message = (error as? AuthError)?.localizedDescription ?? "Could not connect to Asana. Please try again." }
                }
            }
            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = true
            if authSession?.start() != true { busy = false; message = "Could not open Asana sign-in."; onChange?() }
        } catch { message = "Could not start Asana sign-in."; onChange?() }
    }
    private func save(_ value: String) throws {
        let data = Data(value.utf8)
        var result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            result = SecItemAdd(item as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw AuthError("Could not save authorization in macOS Keychain.") }
    }
    private func exchange(_ values: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://yadot.netlify.app/.netlify/functions/asana-token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(values)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError("Asana sign-in could not be renewed. Reconnect your account.") }
        return try JSONDecoder().decode(Tokens.self, from: data)
    }
    func accessToken() async throws -> String {
        if let cachedToken, Date() < expires { return cachedToken }
        let current = epoch
        var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let refresh = String(data: data, encoding: .utf8) else { throw AuthError("Connect Asana to load your tasks.") }
        let token = try await exchange(["grant_type":"refresh_token", "refresh_token":refresh])
        guard current == epoch, connected else { throw AuthError("Asana disconnected.") }
        if let next = token.refresh_token { try save(next) }
        cachedToken = token.access_token; expires = Date().addingTimeInterval(Double(token.expires_in ?? 3600) - 60)
        return token.access_token
    }
    func loadWorkspaces() async throws {
        struct Page: Decodable { struct Next: Decodable { let offset: String }; let data: [Workspace]; let next_page: Next? }
        let current = epoch
        let token = try await accessToken()
        var values: [Workspace] = [], offset: String?
        var seen = Set<String>()
        repeat {
            var url = URLComponents(string: "https://app.asana.com/api/1.0/workspaces?limit=100")!
            if let offset { url.queryItems?.append(URLQueryItem(name: "offset", value: offset)) }
            var request = URLRequest(url: url.url!); request.timeoutInterval = 20
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError("Could not list workspaces. Enable workspaces:read in Asana and reconnect.") }
            let page = try JSONDecoder().decode(Page.self, from: data); values += page.data; offset = page.next_page?.offset
            if let offset, !seen.insert(offset).inserted { throw AuthError("Could not finish loading workspaces.") }
        } while offset != nil
        guard current == epoch, connected else { return }
        workspaces = values
        if values.count == 1 { UserDefaults.standard.set(values[0].gid, forKey: "asanaDirectWorkspace") }
    }
    func reloadWorkspaces() {
        guard !busy else { return }; busy = true; onChange?()
        Task {
            defer { busy = false; onChange?() }
            do { try await loadWorkspaces(); message = "Choose your Asana workspace." }
            catch { message = (error as? AuthError)?.localizedDescription ?? "Could not load workspaces." }
        }
    }
    func disconnect() {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { message = "Could not remove authorization from Keychain."; onChange?(); return }
        epoch += 1; cachedToken = nil; expires = .distantPast; workspaces = []
        UserDefaults.standard.set(false, forKey: "asanaOAuthConnected")
        UserDefaults.standard.set(false, forKey: "asanaBriefsEnabled")
        UserDefaults.standard.removeObject(forKey: "asanaDirectWorkspace")
        message = "Disconnected from Today. You can also revoke access in Asana’s Apps settings."
        onChange?()
    }
}
