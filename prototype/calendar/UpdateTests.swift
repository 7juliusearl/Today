import Foundation
import CryptoKit

@main struct UpdateTests {
    static func rejects(_ label: String, _ body: () throws -> Void) {
        do { try body(); fatalError("Expected rejection: \(label)") } catch {}
    }
    static func check(_ value: @autoclosure () throws -> Bool, line: UInt = #line) throws {
        let result = try value()
        assert(result, "Failed check at line \(line)")
    }
    static func write(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    static func fixture(_ root: URL, build: Int, legacy: Bool = false) throws {
        let info: [String: Any] = ["CFBundleIdentifier": "com.today-dashboard.portable", "CFBundleVersion": String(build), "CFBundleShortVersionString": "0.\(build).0"]
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Today.app/Contents/Resources/dashboard"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: root.appendingPathComponent("Today.app/Contents/Info.plist"))
        try write("Today", root.appendingPathComponent("TODAY-PROJECT.txt"))
        try write("release \(build)", root.appendingPathComponent("dashboard/index.html"))
        try write("release \(build)", root.appendingPathComponent("Today.app/Contents/Resources/dashboard/index.html"))
        try write("personal schedule", root.appendingPathComponent("data/schedule.js"))
        try write("custom color", root.appendingPathComponent("custom/user.css"))
        if !legacy {
            let baseline = TodayBaseline(version: "0.\(build).0", build: build, dashboard: try TodayUpdateFiles.inventory(root.appendingPathComponent("dashboard")))
            try JSONEncoder().encode(baseline).write(to: root.appendingPathComponent(".today-release.json"))
        }
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("TodayUpdateTests-\(UUID().uuidString)").resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let release = TodayRelease(version: "0.2.0", build: 2, notes: "Test", url: "https://www.dropbox.com/scl/fi/example/Today.zip?rlkey=keep&dl=0", sha256: String(repeating: "a", count: 64), bytes: 10)
        let payload = try JSONEncoder().encode(release)
        let signed = SignedTodayRelease(payload: payload.base64EncodedString(), signature: try key.signature(for: payload).base64EncodedString())
        let envelope = try JSONEncoder().encode(signed)
        try check(TodayUpdateFiles.verifiedRelease(envelope, publicKey: key.publicKey.rawRepresentation).build == 2)
        rejects("wrong signing key") { _ = try TodayUpdateFiles.verifiedRelease(envelope, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation) }
        let changed = SignedTodayRelease(payload: Data("tampered".utf8).base64EncodedString(), signature: signed.signature)
        rejects("tampered metadata") { _ = try TodayUpdateFiles.verifiedRelease(JSONEncoder().encode(changed), publicKey: key.publicKey.rawRepresentation) }
        rejects("Dropbox login HTML") { _ = try TodayUpdateFiles.verifiedRelease(Data("<html>login</html>".utf8), publicKey: key.publicKey.rawRepresentation) }
        let direct = try TodayUpdateFiles.downloadURL(release.url).absoluteString
        assert(direct.contains("rlkey=keep") && direct.contains("dl=1") && !direct.contains("dl=0"))
        rejects("insecure URL") { _ = try TodayUpdateFiles.downloadURL("http://example.com/update") }
        rejects("folder URL") { _ = try TodayUpdateFiles.downloadURL("https://www.dropbox.com/scl/fo/folder?dl=0") }
        let old = root.appendingPathComponent("Existing Today")
        let fresh = root.appendingPathComponent("New Today")
        try fixture(old, build: 1, legacy: true)
        try fixture(fresh, build: 2)
        try check(TodayUpdateFiles.conflicts(old).isEmpty)
        try write("modified layout", old.appendingPathComponent("dashboard/index.html"))
        rejects("legacy customization") { _ = try TodayUpdateFiles.install(from: fresh, into: old) }
        try check(String(contentsOf: old.appendingPathComponent("dashboard/index.html"), encoding: .utf8) == "modified layout")
        try write("release 1", old.appendingPathComponent("dashboard/index.html"))
        try write("personal instructions", old.appendingPathComponent("AGENTS.md"))
        rejects("interrupted staging") { _ = try TodayUpdateFiles.install(from: fresh, into: old, beforeSwap: { throw TodayUpdateError("disk full") }) }
        try check(String(contentsOf: old.appendingPathComponent("dashboard/index.html"), encoding: .utf8) == "release 1")
        rejects("failed promotion rolls back") { _ = try TodayUpdateFiles.install(from: fresh, into: old, beforePromote: { throw TodayUpdateError("simulated rename failure") }) }
        try check(String(contentsOf: old.appendingPathComponent("dashboard/index.html"), encoding: .utf8) == "release 1")
        let backup = try TodayUpdateFiles.install(from: fresh, into: old)
        try check(String(contentsOf: old.appendingPathComponent("dashboard/index.html"), encoding: .utf8) == "release 2")
        try check(String(contentsOf: backup.appendingPathComponent("dashboard/index.html"), encoding: .utf8) == "release 1")
        try check(String(contentsOf: old.appendingPathComponent("data/schedule.js"), encoding: .utf8) == "personal schedule")
        try check(String(contentsOf: old.appendingPathComponent("custom/user.css"), encoding: .utf8) == "custom color")
        try check(String(contentsOf: old.appendingPathComponent("AGENTS.md"), encoding: .utf8).contains("personal instructions"))
        rejects("same version") { _ = try TodayUpdateFiles.install(from: fresh, into: old) }
        try write("new custom file", old.appendingPathComponent("dashboard/extra.js"))
        try check(TodayUpdateFiles.conflicts(old) == ["extra.js"])
        try fm.removeItem(at: old.appendingPathComponent("dashboard/extra.js"))
        try fm.createSymbolicLink(at: old.appendingPathComponent("dashboard/link.js"), withDestinationURL: old.appendingPathComponent("custom/user.css"))
        rejects("linked dashboard file") { _ = try TodayUpdateFiles.conflicts(old) }
        let badArchive = root.appendingPathComponent("bad.zip")
        try Data("not a zip".utf8).write(to: badArchive)
        rejects("corrupt download") { _ = try TodayUpdateFiles.extract(badArchive, into: root.appendingPathComponent("extract"), release: release) }
        print("PASS: signed releases, wrong keys/tampering, login HTML, HTTPS/Dropbox URLs, v1 migration, custom-edit blocking, backup/personal data preservation, staging failures, rollback, version guard, new-file conflicts, symlink rejection, and corrupt downloads.")
    }
}
