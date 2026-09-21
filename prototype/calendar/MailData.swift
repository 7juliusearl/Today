import AppKit
import Combine
import SwiftUI

struct MailboxChoice: Codable, Identifiable {
    let account: String
    let mailbox: String
    let label: String
    var id: String { account + "\n" + mailbox }
}
struct MailItem: Codable {
    let id: String
    let messageID: String
    let subject: String
    let sender: String
    let attachmentCount: Int
    let receivedAt: String
    let isRead: Bool?
    let threadReferences: [String]?
}
struct MailSnapshot: Codable {
    var items: [MailItem] = []
    var label: String?
    var status: String?
    var updatedAt: String?
}

struct MailReadError: LocalizedError {
    let detail: String
    var errorDescription: String? {
        if detail.contains("-1743") || detail.localizedCaseInsensitiveContains("not authorized") {
            return "Allow Today to access Mail in System Settings → Privacy & Security → Automation, then retry."
        }
        if detail.contains("timeout") { return "Mail took too long to respond. Open Mail, let it finish syncing, then retry." }
        return "Could not read this mailbox. Open Mail and reconnect in Settings."
    }
}

// Mail automation runs in a separate process so a busy Mail app cannot freeze the UI.
func runMailReader(action: String, choice: MailboxChoice? = nil) async throws -> Data {
    let selection = try choice.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) } ?? "{}"
    return try await runLocalAutomation(resource: "read-mail", arguments: [action, selection])
}

func runLocalAutomation(resource: String, arguments: [String]) async throws -> Data {
    guard let path = Bundle.main.url(forResource: resource, withExtension: "js") else { throw URLError(.fileDoesNotExist) }
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", path.path] + arguments
            process.standardOutput = output
            process.standardError = errors
            do {
                try process.run()
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeout.cancel()
                guard process.terminationStatus == 0 else {
                    let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    throw MailReadError(detail: process.terminationReason == .uncaughtSignal ? "timeout" : detail)
                }
                continuation.resume(returning: data)
            } catch { continuation.resume(throwing: error) }
        }
    }
}

@MainActor final class MailModel: ObservableObject {
    @Published var choices: [MailboxChoice] = []
    @Published var selectedID = ""
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "mailEnabled")
    @Published private(set) var busy = false
    @Published private(set) var status = "Connect Apple Mail to choose an inbox."
    var snapshot = MailSnapshot(status: "Connect Apple Mail in Settings.")
    var onChange: (() -> Void)?
    private var selection: MailboxChoice?
    private var lastAttempt = Date.distantPast
    private var generation = 0

    init() {
        if let data = UserDefaults.standard.data(forKey: "mailboxChoice"), let choice = try? JSONDecoder().decode(MailboxChoice.self, from: data) {
            selection = choice; selectedID = choice.id; choices = [choice]
        }
    }
    func connect() {
        guard !busy else { return }
        busy = true; status = "Connecting to Apple Mail…"
        Task {
            defer {
                busy = false
            }
            do {
                choices = try JSONDecoder().decode([MailboxChoice].self, from: await runMailReader(action: "mailboxes"))
                if !choices.contains(where: { $0.id == selectedID }) { selectedID = "" }
                status = choices.isEmpty ? "No mailboxes found. Check your accounts in Apple Mail." : "Choose an inbox or mailbox, then click Use mailbox."
            } catch { status = error.localizedDescription }
        }
    }
    func useSelection() {
        guard let choice = choices.first(where: { $0.id == selectedID }) else { return }
        generation += 1
        selection = choice; enabled = true
        UserDefaults.standard.set(true, forKey: "mailEnabled")
        UserDefaults.standard.set(try? JSONEncoder().encode(choice), forKey: "mailboxChoice")
        snapshot = MailSnapshot(label: choice.label, status: "Reading Mail…")
        onChange?()
        refresh(force: true)
    }
    func disconnect() {
        generation += 1
        enabled = false
        UserDefaults.standard.set(false, forKey: "mailEnabled")
        snapshot = MailSnapshot(status: "Connect Apple Mail in Settings.")
        status = "Mail is disconnected."
        onChange?()
    }
    func refresh(force: Bool = false) {
        guard enabled, let choice = selection, !busy,
              force || Date().timeIntervalSince(lastAttempt) >= 60 else { return }
        lastAttempt = Date(); busy = true
        let current = generation
        Task {
            defer {
                busy = false
            }
            do {
                var result = try JSONDecoder().decode(MailSnapshot.self, from: await runMailReader(action: "read", choice: choice))
                guard enabled && current == generation else { return }
                result.label = choice.label
                result.updatedAt = ISO8601DateFormatter().string(from: Date())
                snapshot = result
                status = "Connected to \(choice.label)."
            } catch {
                guard enabled && current == generation else { return }
                snapshot.status = error.localizedDescription
                status = error.localizedDescription
            }
            onChange?()
        }
    }
    func openMailApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    func openMessage(id: String) {
        guard let item = snapshot.items.first(where: { $0.id == id }), !item.messageID.isEmpty else { return }
        let raw = item.messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard let encoded = ("<" + raw + ">").addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "message://" + encoded) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct MailSettingsView: View {
    @ObservedObject var mail: MailModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple Mail").font(.headline)
            Text("Show today’s mail locally. macOS will ask to allow access to Mail. No messages are sent or changed by refreshing.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(mail.busy ? "Working…" : "Connect / reload mailboxes") { mail.connect() }.disabled(mail.busy)
                if mail.enabled { Button("Disconnect") { mail.disconnect() } }
            }
            if !mail.choices.isEmpty {
                Picker("Mailbox", selection: $mail.selectedID) {
                    Text("Choose…").tag("")
                    ForEach(mail.choices) { choice in Text(choice.label).tag(choice.id) }
                }
                Button("Use mailbox") { mail.useSelection() }.disabled(mail.busy || mail.selectedID.isEmpty)
            }
            Text(mail.status).font(.caption).foregroundStyle(.secondary)
            Text("Mail connection changes apply immediately.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
