import Foundation
import CryptoKit

@main struct UpdatePackageTests {
    static func main() throws {
        let fm = FileManager.default
        let args = CommandLine.arguments
        guard args.count == 3 else { fatalError("Pass new Today.zip and an old portable Today folder") }
        let zip = URL(fileURLWithPath: args[1])
        let oldSource = URL(fileURLWithPath: args[2])
        let root = fm.temporaryDirectory.appendingPathComponent("TodayPackageTest-\(UUID().uuidString)").resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let data = try Data(contentsOf: zip, options: .mappedIfSafe)
        let baselineData = try TodayUpdateFiles.run("/usr/bin/unzip", ["-p", zip.path, "Today/.today-release.json"])
        let baseline = try JSONDecoder().decode(TodayBaseline.self, from: Data(baselineData.utf8))
        let release = TodayRelease(version: baseline.version, build: baseline.build, notes: "Fixture", url: "https://example.com/Today.zip", sha256: TodayUpdateFiles.hash(data), bytes: data.count)
        let source = try TodayUpdateFiles.extract(zip, into: root.appendingPathComponent("unpacked"), release: release)
        let target = root.appendingPathComponent("Coworker Today")
        try fm.copyItem(at: oldSource, to: target)
        try "window.WORK_SCHEDULE = { personal: true };".write(to: target.appendingPathComponent("data/schedule.js"), atomically: true, encoding: .utf8)
        let prior = try TodayUpdateFiles.inventory(target.appendingPathComponent("data"))
        try fm.createDirectory(at: target.appendingPathComponent("custom"), withIntermediateDirectories: true)
        try ".greeting { color: purple; }".write(to: target.appendingPathComponent("custom/user.css"), atomically: true, encoding: .utf8)
        // A v1 user might have created only user.css when migrating their changes.
        let backup = try TodayUpdateFiles.install(from: source, into: target)
        try TodayUpdateFiles.validatePackage(target)
        let after = try TodayUpdateFiles.inventory(target.appendingPathComponent("data"))
        assert(prior == after)
        let custom = try String(contentsOf: target.appendingPathComponent("custom/user.css"), encoding: .utf8)
        assert(custom.contains("purple"))
        assert(fm.fileExists(atPath: backup.appendingPathComponent("Today.app").path))
        let installed = try TodayUpdateFiles.conflicts(target)
        assert(installed.isEmpty)
        print("PASS: real universal ZIP verified/extracted; real v1 folder migrated; installed app signature verified; personal data and customization preserved; complete backup retained. No real user app or permissions changed.")
    }
}
