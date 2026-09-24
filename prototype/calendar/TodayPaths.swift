import AppKit
import Security

@MainActor enum TodayPaths {
    static var portable: Bool { Bundle.main.object(forInfoDictionaryKey: "TodayPortable") as? Bool == true }
    static func isProject(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("dashboard/index.html").path) &&
        FileManager.default.fileExists(atPath: url.appendingPathComponent("TODAY-PROJECT.txt").path)
    }
    static var project: URL? {
        guard portable else { return nil }
        let besideApp = Bundle.main.bundleURL.deletingLastPathComponent()
        if isProject(besideApp) {
            UserDefaults.standard.set(besideApp.path, forKey: "portableProject")
            return besideApp
        }
        if let path = UserDefaults.standard.string(forKey: "portableProject"), isProject(URL(fileURLWithPath: path)) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
    static var updateInstallationIssue: String? {
        guard portable else { return "This is the development copy. Install coworker updates from the Today app in your downloaded Today folder." }
        guard let project else { return "Today can’t find its full app folder. Choose the Today folder containing Today.app, dashboard, and data before updating." }
        guard Self.matchesInstalledApp(running: Bundle.main.bundleURL, installed: project.appendingPathComponent("Today.app")) else {
            return "Today’s saved installation doesn’t match this running copy. Choose the Today folder for this copy before updating. Your files haven’t been changed."
        }
        return nil
    }
    // App Translocation changes the launch path, not the signed code identity.
    // Accept only the same validated code from the installation already in use.
    static func matchesInstalledApp(running: URL, installed: URL) -> Bool {
        if running.standardizedFileURL == installed.standardizedFileURL { return true }
        func identity(_ url: URL) -> Data? {
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
                  SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { return nil }
            var information: CFDictionary?
            guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
                  let info = information as? [String: Any],
                  info[kSecCodeInfoIdentifier as String] as? String == "com.today-dashboard.portable" else { return nil }
            return info[kSecCodeInfoUnique as String] as? Data
        }
        guard let runningID = identity(running), let installedID = identity(installed) else { return false }
        return runningID == installedID
    }
    static func showUpdateFolder() {
        if let project {
            NSWorkspace.shared.activateFileViewerSelecting([project.appendingPathComponent("Today.app")])
        } else { chooseProject() }
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
