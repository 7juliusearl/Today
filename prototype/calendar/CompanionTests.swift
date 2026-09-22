import Foundation

@main struct CompanionTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("today-companion-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "<html><head></head><body><script src=\"app.js?v=26\"></script></body></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        for file in ["app.js", "styles.css", "overview.css", "companion.js", "companion.css", "manifest.json"] {
            try "fixture".write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        let server = CompanionServer(dashboardRoot: root, resourceRoot: root)
        server.snapshot = "window.DASHBOARD_DATA = {fixture:true};"
        server.start()
        guard let link = server.links.first, let url = URL(string: link), let secret = url.fragment else { fatalError(server.status) }
        let host = "\(url.host!):\(url.port!)"
        func request(_ path: String, method: String = "GET", cookie: String? = nil, origin: String? = nil, hostOverride: String? = nil, body: String = "") -> String {
            var fields = ["host": hostOverride ?? host]
            fields["cookie"] = cookie; fields["origin"] = origin
            return String(decoding: server.response(method: method, path: path, fields: fields, body: body), as: UTF8.self)
        }
        func check(_ ok: Bool, _ name: String) { precondition(ok, name) }
        let cookie = "today_companion=" + secret
        check(request("/").contains("Connect to Today"), "Pairing shell")
        check(request("/snapshot").hasPrefix("HTTP/1.1 401"), "No unauthenticated data")
        check(request("/dashboard").hasPrefix("HTTP/1.1 401"), "No unauthenticated dashboard")
        check(request("/pair", method: "POST", origin: "http://" + host, body: "wrong").hasPrefix("HTTP/1.1 403"), "Reject wrong token")
        check(request("/pair", method: "POST", body: secret).hasPrefix("HTTP/1.1 403"), "Pair requires same origin")
        check(request("/pair", method: "POST", origin: "http://" + host, body: secret).contains("HttpOnly; SameSite=Strict"), "Paired cookie")
        check(request("/snapshot", cookie: cookie).contains("fixture:true"), "Paired snapshot")
        check(request("/snapshot", cookie: cookie, origin: "https://evil.example").hasPrefix("HTTP/1.1 403"), "Cross-origin denied")
        check(request("/snapshot", cookie: cookie, hostOverride: "evil.example").hasPrefix("HTTP/1.1 403"), "DNS rebinding host denied")
        check(request("/dashboard", cookie: cookie).contains("companion.js"), "Companion bootstrap replaces native entrypoint")
        for path in ["/../data/dashboard.js", "/%2e%2e/data/dashboard.js", "/data/schedule.js", "/.git/config"] {
            check(request(path, cookie: cookie).hasPrefix("HTTP/1.1 404"), "No arbitrary file access")
        }
        check(request("/snapshot", method: "POST", cookie: cookie).hasPrefix("HTTP/1.1 405"), "No remote commands")
        server.stop()
        check(request("/snapshot", cookie: cookie).hasPrefix("HTTP/1.1 403"), "Stop revokes session")
        server.start()
        check(request("/snapshot", cookie: cookie).hasPrefix("HTTP/1.1 401"), "Restart rotates token")
        server.stop()
        print("Companion request tests passed")
    }
}
