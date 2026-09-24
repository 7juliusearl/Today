import AppKit
import SwiftUI

// HTTPS only, including redirects. The release signature is checked independently of the host.
final class UpdateNetwork: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
    func fetch(_ url: URL, limit: Int) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https", response.expectedContentLength <= limit else {
            throw TodayUpdateError("The update could not be downloaded. Check the shared file link and try again.")
        }
        var result = Data()
        for try await byte in bytes {
            guard result.count < limit else { throw TodayUpdateError("The update download is larger than expected.") }
            result.append(byte)
        }
        return result
    }
}

@MainActor final class TodayUpdater: ObservableObject {
    static let shared = TodayUpdater()
    @Published var feed: String
    @Published var status = ""
    @Published var busy = false
    @Published var available: TodayRelease?
    @Published var automatic: Bool { didSet { UserDefaults.standard.set(automatic, forKey: "automaticUpdateChecks") } }
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    private var checkedFeed = ""
    private var lastCheck = Date.distantPast
    init() {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "TodayUpdateFeedURL") as? String ?? ""
        let saved = UserDefaults.standard.string(forKey: "updateFeedURL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        feed = saved.isEmpty ? bundled : saved
        automatic = UserDefaults.standard.object(forKey: "automaticUpdateChecks") as? Bool ?? true
    }
    func saveFeed() {
        UserDefaults.standard.set(feed.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "updateFeedURL")
        available = nil
        status = "Update source saved."
    }
    func checkAutomatically() {
        guard automatic, !feed.isEmpty, Date().timeIntervalSince(lastCheck) > 21600 else { return }
        Task { await check(silent: true) }
    }
    func check(silent: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        lastCheck = Date()
        available = nil
        if !silent { status = "Checking for updates…" }
        do {
            let source = try TodayUpdateFiles.downloadURL(feed)
            guard let encoded = Bundle.main.object(forInfoDictionaryKey: "TodayUpdatePublicKey") as? String,
                  let publicKey = Data(base64Encoded: encoded) else { throw TodayUpdateError("This build has no release verification key.") }
            let data = try await UpdateNetwork().fetch(source, limit: 64 * 1024)
            let release = try TodayUpdateFiles.verifiedRelease(data, publicKey: publicKey)
            let current = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
            if release.build > current {
                available = release
                checkedFeed = feed
                status = "Today \(release.version) is available."
            } else { status = "You’re up to date (\(version))." }
        } catch { if !silent { status = error.localizedDescription } }
    }

    func install() async {
        guard !busy, let release = available, checkedFeed == feed else { return }
        busy = true
        defer { busy = false }
        do {
            if let issue = TodayPaths.updateInstallationIssue { throw TodayUpdateError(issue) }
            guard let project = TodayPaths.project else { throw TodayUpdateError("Choose your Today folder before updating.") }
            try TodayUpdateFiles.requireProject(project)
            try TodayUpdateFiles.requireUnmodified(project)
            status = "Downloading Today \(release.version)…"
            let archive = try await UpdateNetwork().fetch(TodayUpdateFiles.downloadURL(release.url), limit: release.bytes)
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("TodayUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var handedOff = false
            defer { if !handedOff { try? FileManager.default.removeItem(at: staging) } }
            let zip = staging.appendingPathComponent("Today.zip")
            try archive.write(to: zip)
            status = "Verifying the update…"
            let source = try await Task.detached { try TodayUpdateFiles.extract(zip, into: staging.appendingPathComponent("unpacked"), release: release) }.value
            try TodayUpdateFiles.requireUnmodified(project)
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/TodayUpdateHelper")
            let process = Process()
            process.executableURL = helper
            process.arguments = ["--install", source.path, project.path, String(ProcessInfo.processInfo.processIdentifier)]
            try process.run()
            handedOff = true
            status = "Restarting Today…"
            NSApp.terminate(nil)
        } catch { status = error.localizedDescription }
    }
}

struct TodayUpdateSettings: View {
    @ObservedObject var updater = TodayUpdater.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Updates").font(.headline)
            Text("Today \(updater.version) · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Check for updates") { Task { await updater.check() } }.disabled(updater.busy || updater.feed.isEmpty)
                if updater.busy { ProgressView().controlSize(.small) }
            }
            Text("Updates are delivered through Today’s built-in update service. No setup needed.").font(.caption).foregroundStyle(.secondary)
            Toggle("Check for updates automatically", isOn: $updater.automatic)
            Text("Checks on launch and every six hours while Today is open. Installation always waits for you.").font(.caption).foregroundStyle(.secondary)
            if let release = updater.available {
                Text(release.notes).font(.callout)
                if let issue = TodayPaths.updateInstallationIssue {
                    Label("Locate this Today installation", systemImage: "folder.badge.questionmark").font(.headline)
                    Text(issue).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if TodayPaths.portable {
                        Button("Locate Today installation…") {
                            TodayPaths.chooseProject()
                            updater.objectWillChange.send()
                        }
                        if let project = TodayPaths.project { Text(project.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                } else {
                    Button("Install update and restart") { Task { await updater.install() } }.disabled(updater.busy)
                }
                Text("Your existing folder is backed up beside Today. Personal data and custom/ files are kept. Changes made directly in dashboard/ must be migrated first.").font(.caption).foregroundStyle(.secondary)
            }
            if !updater.status.isEmpty { Text(updater.status).font(.caption).textSelection(.enabled) }
            if !TodayPaths.portable {
                DisclosureGroup("Developer update settings") {
                    TextField("Update source", text: $updater.feed).textFieldStyle(.roundedBorder).disabled(updater.busy)
                    Button("Save update source") { updater.saveFeed() }.disabled(updater.busy)
                }.font(.caption)
            }
            if !TodayPaths.portable { Text("You’re using the development copy. Installation is available in the coworker copy.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
