import Foundation
import Security

// Developer trial only: the coworker app never reads the developer's OAuth secret.
@MainActor final class AsanaBriefs {
    let auth = AsanaAuth()
    init() {
        auth.onChange = { [weak self] in
            guard let self else { return }
            self.generation += 1; self.assigned = nil; self.assignedChecked = .distantPast; self.cache.removeAll(); self.checked.removeAll()
            self.onChange?()
        }
    }
    private struct Credentials: Codable {
        let client_id: String
        let client_secret: String
        var refresh_token: String
    }
    private struct APITask: Decodable {
        struct Parent: Decodable { let gid: String }
        let name: String
        let notes: String?
        let permalink_url: String?
        let parent: Parent?
    }
    private struct Envelope: Decodable { let data: APITask }
    private struct Token: Decodable { let access_token: String; let refresh_token: String? }
    private struct Failure: Error { let message: String }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    private var cache: [String: AsanaBrief] = [:]
    private var checked: [String: Date] = [:]
    private var fetching = false
    private var generation = 0
    private var source = ""
    private var assignedChecked = Date.distantPast
    private var assigned: [AsanaPayload.Task]?
    var workspace: String { UserDefaults.standard.string(forKey: "asanaDirectWorkspace") ?? "" }
    var directTasks: [AsanaPayload.Task]? { enabled && !workspace.isEmpty ? assigned : nil }
    func setWorkspace(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty || value.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
        UserDefaults.standard.set(value, forKey: "asanaDirectWorkspace")
        generation += 1; assigned = nil; assignedChecked = .distantPast; cache.removeAll(); checked.removeAll()
        onChange?()
    }
    var onChange: (() -> Void)?
    var status = "Assigned tasks and parent briefs load here after connecting."
    var enabled: Bool { (auth.connected || !TodayPaths.portable) && !auth.busy && UserDefaults.standard.object(forKey: "asanaBriefsEnabled") as? Bool != false }

    static func taskID(_ text: String?) -> String? {
        guard let text, let url = URLComponents(string: text), url.scheme == "https", url.host == "app.asana.com", url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let digits: (String) -> Bool = { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
        if let i = parts.firstIndex(of: "task"), i + 1 < parts.count, digits(parts[i+1]) { return parts[i+1] }
        if parts.first == "0", parts.count >= 3, digits(parts[1]), digits(parts[2]) { return parts[2] }
        return nil
    }
    func brief(for url: String?) -> AsanaBrief? { enabled ? Self.taskID(url).flatMap { cache[$0] } : nil }
    func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "asanaBriefsEnabled")
        generation += 1; assigned = nil; assignedChecked = .distantPast; cache.removeAll(); checked.removeAll()
        status = value ? "Ready to load parent briefs." : "Direct Asana details are off."
        onChange?()
    }
    func refresh(_ tasks: [AsanaPayload.Task], source: String) {
        guard enabled else { return }
        if self.source != source {
            self.source = source; generation += 1; assigned = nil; assignedChecked = .distantPast; cache.removeAll(); checked.removeAll()
        }
        guard !fetching else { return }
        let today = DateFormatter(); today.dateFormat = "yyyy-MM-dd"; today.locale = Locale(identifier: "en_US_POSIX")
        let ids = Array(Set((directTasks ?? tasks).filter { $0.dueDate == today.string(from: Date()) }.compactMap { Self.taskID($0.url) })).sorted()
        cache = cache.filter { ids.contains($0.key) }
        var pending = Array(ids.filter { Date().timeIntervalSince(checked[$0] ?? .distantPast) > 300 }.prefix(30))
        let loadAssigned = !workspace.isEmpty && Date().timeIntervalSince(assignedChecked) > 300
        guard !pending.isEmpty || loadAssigned else { return }
        fetching = true
        let current = generation
        Task {
            defer { fetching = false; onChange?() }
            do {
                let token = try await accessToken()
                guard current == generation, enabled else { return }
                if loadAssigned {
                    assigned = try await fetchAssigned(token: token, workspace: workspace)
                    guard current == generation, enabled else { assigned = nil; return }
                    assignedChecked = Date()
                    let directIDs = Set((assigned ?? []).filter { $0.dueDate == today.string(from: Date()) }.compactMap { Self.taskID($0.url) })
                    pending = Array(directIDs.filter { Date().timeIntervalSince(checked[$0] ?? .distantPast) > 300 }.sorted().prefix(30))
                    status = "Connected. Assigned tasks come directly from Asana; no calendar subscription needed."
                }
                for id in pending {
                    guard current == generation, enabled else { return }
                    do {
                        let task = try await fetch(id, token: token)
                        var parent: APITask?
                        var message: String?
                        if let parentID = task.parent?.gid {
                            do { parent = try await fetch(parentID, token: token) }
                            catch { message = "Parent brief unavailable. Open the parent task in Asana to check access." }
                        }
                        guard current == generation, enabled else { return }
                        cache[id] = AsanaBrief(title: task.name, description: task.notes ?? "", url: task.permalink_url,
                            parentTitle: parent?.name, parentDescription: parent?.notes, parentURL: parent?.permalink_url, message: message)
                        status = "Connected. Parent briefs refresh every five minutes while Today refreshes."
                    } catch {
                        guard current == generation, enabled else { return }
                        cache.removeValue(forKey: id)
                        status = (error as? Failure)?.message ?? "Could not load Asana details. Calendar tasks remain available."
                    }
                    checked[id] = Date()
                }
            } catch {
                guard current == generation, enabled else { return }
                if loadAssigned { assignedChecked = Date(); assigned = nil }
                for id in pending { checked[id] = Date(); cache.removeValue(forKey: id) }
                status = (error as? Failure)?.message ?? "Connect Asana in Settings to load assigned tasks and parent briefs."
            }
        }
    }
    private func fetchAssigned(token: String, workspace: String) async throws -> [AsanaPayload.Task] {
        struct Page: Decodable {
            struct Next: Decodable { let offset: String }
            let data: [AsanaAssignedTask]
            let next_page: Next?
        }
        guard !workspace.isEmpty, workspace.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw Failure(message: "Choose an Asana workspace.") }
        var records: [AsanaAssignedTask] = []
        var offset: String?
        var seen = Set<String>()
        repeat {
            var url = URLComponents(string: "https://app.asana.com/api/1.0/tasks")!
            url.queryItems = [URLQueryItem(name: "workspace", value: workspace), URLQueryItem(name: "assignee", value: "me"),
                URLQueryItem(name: "completed_since", value: ISO8601DateFormatter().string(from: Date())),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "opt_fields", value: "gid,name,completed,due_on,due_at,notes,permalink_url")]
            if let offset { url.queryItems?.append(URLQueryItem(name: "offset", value: offset)) }
            var request = URLRequest(url: url.url!); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let page = try JSONDecoder().decode(Page.self, from: await data(request))
            records += page.data
            offset = page.next_page?.offset
            if let offset, !seen.insert(offset).inserted { throw Failure(message: "Asana pagination stalled. Try refreshing later.") }
            if records.count > 10000 { throw Failure(message: "Too many assigned tasks to load. Calendar tasks remain available.") }
        } while offset != nil
        return assignedAsanaTasks(records, now: Date())
    }
    private func data(_ request: URLRequest) async throws -> Data {
        var request = request; request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw Failure(message: "Asana could not provide details. Check the connection and task permissions.")
        }
        return data
    }
    private func fetch(_ id: String, token: String) async throws -> APITask {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw Failure(message: "Invalid Asana task link.") }
        var request = URLRequest(url: URL(string: "https://app.asana.com/api/1.0/tasks/\(id)?opt_fields=name,notes,parent.gid,permalink_url")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try JSONDecoder().decode(Envelope.self, from: await data(request)).data
    }
    private func accessToken() async throws -> String {
        if auth.connected { return try await auth.accessToken() }
        guard !TodayPaths.portable else { throw Failure(message: "Connect your Asana account in Settings.") }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.today-dashboard.asana-developer-trial", kSecAttrAccount as String: "developer"]
        var read = query
        read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess, let stored = result as? Data else {
            throw Failure(message: "Connect the private Asana trial on this Mac to load parent briefs.")
        }
        var credentials = try JSONDecoder().decode(Credentials.self, from: stored)
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"), URLQueryItem(name: "client_id", value: credentials.client_id), URLQueryItem(name: "client_secret", value: credentials.client_secret), URLQueryItem(name: "refresh_token", value: credentials.refresh_token)]
        var request = URLRequest(url: URL(string: "https://app.asana.com/-/oauth_token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let token = try JSONDecoder().decode(Token.self, from: await data(request))
        if let refresh = token.refresh_token, refresh != credentials.refresh_token {
            credentials.refresh_token = refresh
            let updated = try JSONEncoder().encode(credentials)
            guard SecItemUpdate(query as CFDictionary, [kSecValueData as String: updated] as CFDictionary) == errSecSuccess else { throw Failure(message: "Could not save renewed Asana authorization in Keychain.") }
        }
        return token.access_token
    }
}
