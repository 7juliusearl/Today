import AppKit

@MainActor enum TodayPaths {
    static var portable: Bool { Bundle.main.object(forInfoDictionaryKey: "TodayPortable") as? Bool == true }
    static func isProject(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("dashboard/index.html").path) &&
        FileManager.default.fileExists(atPath: url.appendingPathComponent("TODAY-PROJECT.txt").path)
    }
    static var project: URL? {
        guard portable else { return nil }
        let besideApp = Bundle.main.bundleURL.deletingLastPathComponent()
        if isProject(besideApp) { return besideApp }
        if let path = UserDefaults.standard.string(forKey: "portableProject"), isProject(URL(fileURLWithPath: path)) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
    static var dashboard: URL {
        project?.appendingPathComponent("dashboard") ?? Bundle.main.resourceURL!.appendingPathComponent("dashboard")
    }
    static var personalData: URL? {
        if portable { return project?.appendingPathComponent("data") }
        return (Bundle.main.object(forInfoDictionaryKey: "TodayPersonalDataDirectory") as? String).map { URL(fileURLWithPath: $0) }
    }
    // macOS may relocate downloaded apps at launch. Ask for the original folder
    // instead of guessing a path or disabling system protections.
    static func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the Today folder containing dashboard, data, and TODAY-PROJECT.txt."
        panel.prompt = "Use Today folder"
        if panel.runModal() == .OK, let url = panel.url {
            if isProject(url) { UserDefaults.standard.set(url.path, forKey: "portableProject") }
            else {
                let alert = NSAlert()
                alert.messageText = "That isn’t a Today project folder."
                alert.informativeText = "Choose the whole folder you received, not Today.app or its dashboard subfolder."
                alert.runModal()
            }
        }
    }
}
