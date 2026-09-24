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
    var isRead: Bool?
    let threadReferences: [String]?
    let stickyBody: String?
}
struct MailSnapshot: Codable {
    var items: [MailItem] = []
    var stickyNotesEnabled: Bool = false
    var stickyScope: String?
    var label: String?
    var status: String?
    var updatedAt: String?
}

// The reader returns mail data only; app preferences are applied after decoding.
extension MailSnapshot {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        items = try values.decodeIfPresent([MailItem].self, forKey: .items) ?? []
        stickyNotesEnabled = try values.decodeIfPresent(Bool.self, forKey: .stickyNotesEnabled) ?? false
        stickyScope = try values.decodeIfPresent(String.self, forKey: .stickyScope)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
    }
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
func runMailReader(action: String, choice: MailboxChoice? = nil, stickyNotes: Bool = false) async throws -> Data {
    let selection = try choice.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) } ?? "{}"
    return try await runLocalAutomation(resource: "read-mail", arguments: [action, selection, stickyNotes ? "true" : "false"])
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
    @Published var receiveStickyNotes = UserDefaults.standard.object(forKey: "receiveStickyNotes") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(receiveStickyNotes, forKey: "receiveStickyNotes")
            snapshot.stickyNotesEnabled = enabled && receiveStickyNotes
            onChange?()
            refresh(force: true)
        }
    }
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
    private var pendingReads = Set<String>()

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
                var result = try JSONDecoder().decode(MailSnapshot.self, from: await runMailReader(action: "read", choice: choice, stickyNotes: receiveStickyNotes))
                guard enabled && current == generation else { return }
                result.stickyNotesEnabled = receiveStickyNotes
                result.stickyScope = choice.id
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
        guard NSWorkspace.shared.open(url), enabled, let choice = selection else { return }
        let current = generation
        let key = "\(current):\(id)"
        guard pendingReads.insert(key).inserted else { return }
        Task {
            defer { pendingReads.remove(key) }
            do {
                try await Task.sleep(for: .seconds(3))
                while busy && enabled && current == generation {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard enabled && current == generation else { return }
                busy = true
                defer { busy = false }
                let mailbox = String(decoding: try JSONEncoder().encode(choice), as: UTF8.self)
                let target = String(decoding: try JSONEncoder().encode(["id": item.id, "messageID": item.messageID]), as: UTF8.self)
                _ = try await runLocalAutomation(resource: "read-mail", arguments: ["mark-read", mailbox, target])
                guard enabled && current == generation else { return }
                if let index = snapshot.items.firstIndex(where: { $0.id == item.id && $0.messageID == item.messageID }) {
                    snapshot.items[index].isRead = true
                }
                snapshot.status = nil
                onChange?()
            } catch {
                guard enabled && current == generation else { return }
                status = "Couldn’t mark this message as read. Try opening it again in Mail."
                snapshot.status = status
                onChange?()
            }
        }
    }
}

struct MailSettingsView: View {
    @ObservedObject var mail: MailModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple Mail").font(.headline)
            Text("Show today’s mail locally. macOS will ask to allow access to Mail. Refreshing never changes messages. Opening an email marks that message as read after a few seconds.")
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
            Toggle("Receive sticky notes", isOn: $mail.receiveStickyNotes)
            Text("Emails titled ‘sticky note’ (any capitalization) become paper notes on your dashboard. Today reads the body only for matching notes. They stay in Apple Mail but are hidden from Today’s emails while this is on. Turning this off shows them as normal emails. Notes may also appear on your paired devices.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Mail connection changes apply immediately.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
