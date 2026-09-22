import AppKit
import Darwin

@main struct TodayUpdateHelper {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let source: URL
            let target: URL
            var parentPID: pid_t?
            if args.count == 2 && args[0] == "--choose" {
                source = URL(fileURLWithPath: args[1])
                let chooser = NSOpenPanel()
                chooser.canChooseDirectories = true
                chooser.canChooseFiles = false
                chooser.allowsMultipleSelection = false
                chooser.message = "Choose your EXISTING Today folder. Your personal data will be kept and the old folder backed up."
                chooser.prompt = "Update this Today"
                app.activate(ignoringOtherApps: true)
                guard chooser.runModal() == .OK, let selected = chooser.url else { return }
                target = selected
            } else if args.count == 4 && args[0] == "--install", let pid = Int32(args[3]) {
                source = URL(fileURLWithPath: args[1])
                target = URL(fileURLWithPath: args[2])
                parentPID = pid
            } else { throw TodayUpdateError("Open Update Existing Today.command from the new release folder.") }
            guard source.standardizedFileURL != target.standardizedFileURL else { throw TodayUpdateError("Choose your old Today folder, not the downloaded release folder.") }
            guard !source.path.hasPrefix(target.path + "/"), !target.path.hasPrefix(source.path + "/") else { throw TodayUpdateError("Keep the new release and your existing Today folder separate.") }
            try TodayUpdateFiles.validatePackage(source)
            try TodayUpdateFiles.requireProject(target)
            try TodayUpdateFiles.requireUnmodified(target)
            let lock = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent)-update.lock")
            let fd = Darwin.open(lock.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd >= 0 else { throw TodayUpdateError("Another update may be running. If a previous update was interrupted, quit Today and remove \(lock.lastPathComponent) beside its folder before trying again.") }
            close(fd)
            defer { try? FileManager.default.removeItem(at: lock) }
            let installedApp = target.appendingPathComponent("Today.app").standardizedFileURL
            if parentPID == nil {
                let alert = NSAlert()
                alert.messageText = "Update your existing Today?"
                alert.informativeText = "Today will quit and restart. Your personal setup is kept. A complete backup will be saved beside your current folder."
                alert.addButton(withTitle: "Update and restart")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                for running in NSWorkspace.shared.runningApplications where running.bundleURL?.standardizedFileURL == installedApp { running.terminate() }
            }
            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline {
                let parentAlive = parentPID.map { kill($0, 0) == 0 } ?? false
                let targetAlive = NSWorkspace.shared.runningApplications.contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.bundleURL?.standardizedFileURL == installedApp && !$0.isTerminated }
                if !parentAlive && !targetAlive { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
            if let pid = parentPID, kill(pid, 0) == 0 { throw TodayUpdateError("Today did not quit. Close it and try again; nothing was replaced.") }
            guard !NSWorkspace.shared.runningApplications.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.bundleURL?.standardizedFileURL == installedApp && !$0.isTerminated }) else { throw TodayUpdateError("Quit Today before installing this update.") }
            let backup = try TodayUpdateFiles.install(from: source, into: target)
            try "Updated successfully. Previous version: \(backup.path)\nTo restore: quit Today, move the updated folder aside, and move this backup back to the original folder path.\n".write(to: target.appendingPathComponent("UPDATE-RESULT.txt"), atomically: true, encoding: .utf8)
            _ = try TodayUpdateFiles.run("/usr/bin/open", [target.appendingPathComponent("Today.app").path])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Today update needs attention"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            app.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
