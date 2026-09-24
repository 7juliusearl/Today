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
    private var mentionPeople: [[String: String]] = []
    private var peopleGeneration = -1
    private var peopleChecked = Date.distantPast
    func users(taskURL: String) async throws -> [String: Any] {
        guard enabled, auth.connected, !workspace.isEmpty,
              let id = Self.taskID(taskURL), cache[id] != nil else {
            throw AsanaAuth.AuthError("Connect Asana, choose a workspace, and reopen the brief.")
        }
        let current = generation
        if peopleGeneration == current, Date().timeIntervalSince(peopleChecked) < 300 { return ["users": mentionPeople] }
        let token = try await auth.accessToken()
        var people: [[String: String]] = [], offset: String?, seen = Set<String>()
        repeat {
            guard current == generation, enabled else { throw CancellationError() }
            var url = URLComponents(string: "https://app.asana.com/api/1.0/users")!
            url.queryItems = [URLQueryItem(name: "workspace", value: workspace), URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "opt_fields", value: "gid,name,photo.image_60x60")]
            if let offset { url.queryItems?.append(URLQueryItem(name: "offset", value: offset)) }
            var request = URLRequest(url: url.url!); request.timeoutInterval = 20
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AsanaAuth.AuthError("Could not load coworkers. Reconnect Asana in Settings to approve people access.")
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let rows = object?["data"] as? [[String: Any]] else { throw AsanaAuth.AuthError("Could not read coworkers. Try again.") }
            for row in rows {
                if let gid = row["gid"] as? String, let name = row["name"] as? String {
                    people.append(["id": gid, "name": name, "photo": (row["photo"] as? [String: Any])?["image_60x60"] as? String ?? ""])
                }
            }
            offset = (object?["next_page"] as? [String: Any])?["offset"] as? String
            if let offset, !seen.insert(offset).inserted { throw AsanaAuth.AuthError("Coworker loading stalled. Try again.") }
            guard people.count <= 10000 else { throw AsanaAuth.AuthError("This workspace has too many people to load.") }
        } while offset != nil
        guard current == generation, enabled else { throw CancellationError() }
        mentionPeople = people; peopleGeneration = current; peopleChecked = Date()
        return ["users": people]
    }
    private var postingComments = Set<String>()
    // Only the task represented by a loaded brief, or its verified parent, may be addressed.
    func comments(taskURL: String, parent: Bool, text: String?, offset: String?, mentions: [[String: Any]] = []) async throws -> [String: Any] {
        guard enabled, auth.connected, let id = Self.taskID(taskURL), let brief = cache[id],
              let target = parent ? Self.taskID(brief.parentURL) : id else {
            throw NSError(domain: "Asana", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reconnect Asana in Settings and reopen the task brief."])
        }
        let current = generation
        let isPost = text != nil
        if let text {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 10000,
                  postingComments.insert(target).inserted else {
                throw NSError(domain: "Asana", code: 2, userInfo: [NSLocalizedDescriptionKey: "Enter a comment of up to 10,000 characters and wait for any current post to finish."])
            }
        }
        defer { if isPost { postingComments.remove(target) } }
        let token = try await auth.accessToken()
        guard current == generation, enabled else { throw CancellationError() }
        var url = URLComponents(string: "https://app.asana.com/api/1.0/tasks/\(target)/stories")!
        let commentFields = "gid,resource_subtype,text,html_text,created_at,created_by.name"
        url.queryItems = [URLQueryItem(name: "opt_fields", value: commentFields + (isPost ? "" : ",created_by.gid,created_by.photo.image_60x60"))]
        if !isPost {
            url.queryItems?.append(URLQueryItem(name: "limit", value: "100"))
            if let offset, !offset.isEmpty, offset.count <= 4096 { url.queryItems?.append(URLQueryItem(name: "offset", value: offset)) }
        }
        var request = URLRequest(url: url.url!); request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let text {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: String]
            if mentions.isEmpty { body = ["text": text] }
            else {
                guard peopleGeneration == current else { throw AsanaAuth.AuthError("Reload the coworker picker before posting mentions.") }
                body = ["html_text": try asanaMentionHTML(text, mentions: mentions, users: mentionPeople)]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["data": body])
        }
        var result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
            // Profile photos may require access beyond stories:read. Fall back only
            // for reads; a write must never be retried automatically.
            if !isPost, (result.1 as? HTTPURLResponse)?.statusCode == 403 {
                guard current == generation, enabled else { throw CancellationError() }
                url.queryItems?[0] = URLQueryItem(name: "opt_fields", value: commentFields)
                request.url = url.url
                result = try await session.data(for: request)
            }
        }
        catch {
            throw NSError(domain: "Asana", code: 3, userInfo: [NSLocalizedDescriptionKey: isPost
                ? "Delivery could not be confirmed. Refresh comments or check Asana before posting again to avoid duplicates."
                : "Could not load comments. Check your connection and try again."])
        }
        guard let response = result.1 as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
            let message = [401, 403].contains(status)
                ? "Comment access was denied. Reconnect Asana in Settings to approve comment permissions, and check access to this task."
                : isPost ? "Posting was not confirmed. Refresh comments or check Asana before trying again."
                : "Could not load comments (Asana \(status)). Try refreshing."
            throw NSError(domain: "Asana", code: status, userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard current == generation, enabled else { throw CancellationError() }
        let object = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any]
        guard let object, isPost ? object["data"] is [String: Any] : object["data"] is [[String: Any]] else {
            throw NSError(domain: "Asana", code: 4, userInfo: [NSLocalizedDescriptionKey: isPost
                ? "Asana returned an unexpected response. Refresh comments before posting again to avoid duplicates."
                : "Could not read Asana’s comments. Try refreshing."])
        }
        let records = isPost ? [object["data"] as! [String: Any]] : object["data"] as! [[String: Any]]
        let comments: [[String: Any]] = records.filter { $0["resource_subtype"] as? String == "comment_added" }.map {
            ["id": $0["gid"] as? String ?? "", "text": $0["text"] as? String ?? "",
             "htmlText": $0["html_text"] as? String ?? "",
             "authorID": ($0["created_by"] as? [String: Any])?["gid"] as? String ?? "",
             "avatar": (($0["created_by"] as? [String: Any])?["photo"] as? [String: Any])?["image_60x60"] as? String ?? "",
             "author": ($0["created_by"] as? [String: Any])?["name"] as? String ?? "Asana user",
             "createdAt": $0["created_at"] as? String ?? ""]
        }
        return ["comments": comments, "next": (object["next_page"] as? [String: Any])?["offset"] as? String ?? ""]
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
