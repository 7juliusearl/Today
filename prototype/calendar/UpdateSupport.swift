import Foundation
import CryptoKit

struct TodayUpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct TodayRelease: Codable {
    let version: String
    let build: Int
    let notes: String
    let url: String
    let sha256: String
    let bytes: Int
}

struct SignedTodayRelease: Codable {
    let payload: String
    let signature: String
}

struct TodayBaseline: Codable {
    let version: String
    let build: Int
    let dashboard: [String: String]
}

enum TodayUpdateFiles {
    static let fm = FileManager.default
    static let maxArchiveBytes = 150 * 1024 * 1024

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func downloadURL(_ text: String) throws -> URL {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil else {
            throw TodayUpdateError("Use an HTTPS shared file link, not a folder path.")
        }
        if ["www.dropbox.com", "dropbox.com"].contains(host.lowercased()) {
            if parts.path.contains("/scl/fo/") || parts.path.hasPrefix("/sh/") {
                throw TodayUpdateError("Paste the shared link to latest.json inside the release folder, not the folder link.")
            }
            parts.queryItems = (parts.queryItems ?? []).filter { !["dl", "raw"].contains($0.name) } + [URLQueryItem(name: "dl", value: "1")]
        }
        guard let url = parts.url else { throw TodayUpdateError("The update link is invalid.") }
        return url
    }

    static func verifiedRelease(_ data: Data, publicKey: Data) throws -> TodayRelease {
        guard data.count <= 64 * 1024,
              let envelope = try? JSONDecoder().decode(SignedTodayRelease.self, from: data),
              let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: payload) else {
            throw TodayUpdateError("This is not a verified Today release. Check that the link opens latest.json without signing in.")
        }
        let release = try JSONDecoder().decode(TodayRelease.self, from: payload)
        guard release.build > 0, !release.version.isEmpty, release.bytes > 0,
              release.bytes <= maxArchiveBytes, release.sha256.count == 64,
              release.sha256.allSatisfy({ $0.isHexDigit }) else { throw TodayUpdateError("The release information is invalid.") }
        _ = try downloadURL(release.url)
        return release
    }

    static func inventory(_ root: URL) throws -> [String: String] {
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey], options: []) else {
            throw TodayUpdateError("Cannot read \(root.lastPathComponent).")
        }
        var result: [String: String] = [:]
        for case let item as URL in iterator {
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            if values.isSymbolicLink == true { throw TodayUpdateError("Linked files cannot be updated automatically: \(item.lastPathComponent).") }
            if values.isRegularFile == true && item.lastPathComponent != ".DS_Store" {
                let components = item.resolvingSymlinksInPath().pathComponents
                let relative = components.dropFirst(root.resolvingSymlinksInPath().pathComponents.count).joined(separator: "/")
                result[relative] = hash(try Data(contentsOf: item))
            }
        }
        return result
    }

    static func baseline(_ project: URL) throws -> TodayBaseline {
        try JSONDecoder().decode(TodayBaseline.self, from: Data(contentsOf: project.appendingPathComponent(".today-release.json")))
    }

    static func conflicts(_ project: URL) throws -> [String] {
        let expected: [String: String]
        if fm.fileExists(atPath: project.appendingPathComponent(".today-release.json").path) {
            expected = try baseline(project).dashboard
        } else {
            // v1 shipped the pristine dashboard inside Today.app as well as beside it.
            expected = try inventory(project.appendingPathComponent("Today.app/Contents/Resources/dashboard"))
        }
        let current = try inventory(project.appendingPathComponent("dashboard"))
        return Set(expected.keys).union(current.keys).filter { expected[$0] != current[$0] }.sorted()
    }

    static func requireProject(_ project: URL) throws {
        guard project.isFileURL,
              fm.fileExists(atPath: project.appendingPathComponent("TODAY-PROJECT.txt").path),
              fm.fileExists(atPath: project.appendingPathComponent("Today.app/Contents/Info.plist").path),
              fm.fileExists(atPath: project.appendingPathComponent("dashboard/index.html").path) else {
            throw TodayUpdateError("Choose the existing Today folder containing Today.app, dashboard, and data.")
        }
        let info = try appInfo(project)
        guard info["CFBundleIdentifier"] as? String == "com.today-dashboard.portable" else {
            throw TodayUpdateError("Only coworker copies can be updated here. Rebuild the development app from its project.")
        }
        guard project.standardizedFileURL.path == project.resolvingSymlinksInPath().path else {
            throw TodayUpdateError("Move Today to a regular local folder before updating.")
        }
        for name in ["dashboard", "Today.app", "custom", "data", ".today-release.json"] {
            let item = project.appendingPathComponent(name)
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw TodayUpdateError("The \(name) path is a link. Use a regular local Today folder.")
            }
        }
    }

    static func appInfo(_ project: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: project.appendingPathComponent("Today.app/Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw TodayUpdateError("The app information is unreadable.") }
        return info
    }

    static func requireUnmodified(_ project: URL) throws {
        let changed = try conflicts(project)
        guard changed.isEmpty else {
            throw TodayUpdateError("Your dashboard has custom edits in: \(changed.joined(separator: ", ")). Nothing was replaced. Ask Codex or Claude to move these edits into custom/user.css or custom/user.js, then restore the dashboard files from Today.app/Contents/Resources/dashboard and try again.")
        }
    }

    @discardableResult static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TodayUpdateError("\(URL(fileURLWithPath: executable).lastPathComponent) could not complete the update. \(String(decoding: data.prefix(1200), as: UTF8.self))") }
        return String(decoding: data, as: UTF8.self)
    }

    static func validatePackage(_ project: URL, release: TodayRelease? = nil) throws {
        try requireProject(project)
        let baseline = try baseline(project)
        let info = try appInfo(project)
        guard try inventory(project.appendingPathComponent("dashboard")) == baseline.dashboard,
              Int(info["CFBundleVersion"] as? String ?? "") == baseline.build,
              info["CFBundleShortVersionString"] as? String == baseline.version else { throw TodayUpdateError("The downloaded app and dashboard do not match their release.") }
        if let release, release.build != baseline.build || release.version != baseline.version { throw TodayUpdateError("The download is for a different version.") }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", project.appendingPathComponent("Today.app").path])
    }

    static func extract(_ archive: URL, into directory: URL, release: TodayRelease) throws -> URL {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard data.count == release.bytes, hash(data) == release.sha256 else { throw TodayUpdateError("The download is incomplete or changed. Your existing app is untouched.") }
        // Only publisher-signed, hash-verified archives reach the system extractor.
        let entries = try run("/usr/bin/unzip", ["-Z1", archive.path]).split(separator: "\n")
        guard !entries.isEmpty, entries.allSatisfy({ entry in
            entry.hasPrefix("Today/") && !entry.split(separator: "/").contains("..") && !entry.contains("\\")
        }) else { throw TodayUpdateError("The release archive has unexpected paths.") }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        let project = directory.appendingPathComponent("Today")
        try validatePackage(project, release: release)
        return project
    }

    // Work only in a sibling staging folder until the complete replacement is ready.
    // data/, custom/, and every other personal file survive because we copy the user's folder first.
    static func install(from source: URL, into target: URL, beforeSwap: (() throws -> Void)? = nil, beforePromote: (() throws -> Void)? = nil) throws -> URL {
        try requireProject(target)
        try requireUnmodified(target)
        let oldInfo = try appInfo(target)
        let new = try baseline(source)
        guard new.build > (Int(oldInfo["CFBundleVersion"] as? String ?? "") ?? 0) else { throw TodayUpdateError("This copy already has this version or a newer version.") }
        let parent = target.deletingLastPathComponent()
        let id = UUID().uuidString
        let stage = parent.appendingPathComponent(".Today-stage-\(id)")
        let backup = parent.appendingPathComponent("Today Backups/\(target.lastPathComponent)-\(id)")
        try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: target, to: stage)
        defer { try? fm.removeItem(at: stage) }
        for name in ["Today.app", "dashboard", ".today-release.json"] {
            let destination = stage.appendingPathComponent(name)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source.appendingPathComponent(name), to: destination)
        }
        let custom = stage.appendingPathComponent("custom")
        if !fm.fileExists(atPath: custom.path) { try fm.copyItem(at: source.appendingPathComponent("custom"), to: custom) }
        let guide = source.appendingPathComponent("UPDATES.md")
        if fm.fileExists(atPath: guide.path) {
            let destination = stage.appendingPathComponent("UPDATES.md")
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: guide, to: destination)
        }
        for name in ["AGENTS.md", "CLAUDE.md", "START-HERE.md"] {
            let destination = stage.appendingPathComponent(name)
            let existing = (try? String(contentsOf: destination, encoding: .utf8)) ?? ""
            let note = "<!-- today-update-guidance -->"
            if !existing.contains(note) {
                try "\(note)\nRead UPDATES.md first. Personal edits belong in custom/user.css and custom/user.js; direct edits to dashboard/ block automatic updates. Keep existing personal instructions below.\n\n\(existing)".write(to: destination, atomically: true, encoding: .utf8)
            }
        }
        try requireUnmodified(target) // Catch edits made during staging too.
        try beforeSwap?()
        try fm.moveItem(at: target, to: backup)
        do {
            try beforePromote?()
            try fm.moveItem(at: stage, to: target)
        }
        catch {
            do { try fm.moveItem(at: backup, to: target) }
            catch { throw TodayUpdateError("The update could not finish. Your previous folder is safe at \(backup.path). Move it back to \(target.path).") }
            throw error
        }
        return backup
    }
}
