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
        try FileManager.default.createDirectory(at: root.appendingPathComponent("icons"), withIntermediateDirectories: true)
        try Data([137, 80, 78, 71]).write(to: root.appendingPathComponent("icons/icon-180.png"))
        let suite = "today-companion-tests-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let pairingFile = root.appendingPathComponent("private/pairing")
        let server = CompanionServer(dashboardRoot: root, resourceRoot: root, pairingFile: pairingFile, preferences: preferences)
        server.snapshot = "window.DASHBOARD_DATA = {fixture:true};"
        server.start()
        guard let link = server.links.first, let url = URL(string: link), let secret = url.fragment else { fatalError(server.status) }
        let host = "\(url.host!):\(url.port!)"
        precondition(!url.host!.hasSuffix(".local"), "QR uses network IP")
        func request(_ path: String, method: String = "GET", cookie: String? = nil, origin: String? = nil, hostOverride: String? = nil, body: String = "") -> String {
            var fields = ["host": hostOverride ?? host]
            fields["cookie"] = cookie; fields["origin"] = origin
            return String(decoding: server.response(method: method, path: path, fields: fields, body: body), as: UTF8.self)
        }
        func check(_ ok: Bool, _ name: String) { precondition(ok, name) }
        let cookie = "today_companion=" + secret
        check(request("/").contains("<title>Today</title>"), "Pairing shell")
        check(request("/").contains("Connect a device"), "Device-neutral pairing")
        check(request("/icons/icon-180.png").hasPrefix("HTTP/1.1 200"), "Home Screen artwork available without cookie")
        check(request("/manifest.json").hasPrefix("HTTP/1.1 200"), "Public manifest")
        check(request("/app.js").hasPrefix("HTTP/1.1 401"), "Non-public assets still require pairing")
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
        check(request("/snapshot", cookie: cookie).hasPrefix("HTTP/1.1 200"), "Restart remembers pairing")
        check(server.links.first == link, "Stable pairing bookmark")
        check(request("/dashboard", cookie: cookie).contains("Max-Age=31536000"), "Dashboard renews remembered session")
        server.resumeOnLaunch = true
        server.stop()
        let relaunched = CompanionServer(dashboardRoot: root, resourceRoot: root, pairingFile: pairingFile, preferences: preferences)
        check(relaunched.resumeOnLaunch, "Resume preference persists")
        relaunched.start()
        check(relaunched.response(method: "GET", path: "/snapshot", fields: ["host": host, "cookie": cookie], body: "").starts(with: Data("HTTP/1.1 503".utf8)), "New instance accepts pairing before snapshot ready")
        relaunched.pauseSharing()
        check(!relaunched.resumeOnLaunch, "Explicit pause disables automatic resume")
        relaunched.start()
        relaunched.forgetPairedDevices()
        check(relaunched.response(method: "GET", path: "/snapshot", fields: ["host": host, "cookie": cookie], body: "").starts(with: Data("HTTP/1.1 401".utf8)), "Forget revokes old device")
        check(relaunched.links.first != link, "Forget replaces pairing secret")
        relaunched.stop()
        print("Companion request tests passed")
    }
}
