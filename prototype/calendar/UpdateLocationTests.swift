import Foundation

@main struct UpdateLocationTests {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("TodayLocationTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let original = URL(fileURLWithPath: CommandLine.arguments[1])
        let relocated = root.appendingPathComponent("Today.app")
        try fm.copyItem(at: original, to: relocated)
        assert(TodayPaths.matchesInstalledApp(running: original, installed: original))
        assert(TodayPaths.matchesInstalledApp(running: relocated, installed: original), "Same signed app at a relocated launch path must update")
        assert(!TodayPaths.matchesInstalledApp(running: relocated, installed: root.appendingPathComponent("Missing.app")))
        let info = relocated.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as! [String: Any]
        plist["CFBundleVersion"] = "99999"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: info)
        assert(!TodayPaths.matchesInstalledApp(running: relocated, installed: original), "Changed or invalid app must be rejected")
        print("PASS direct launch, relocated signed copy, missing installation, and altered app rejection")
    }
}
