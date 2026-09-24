import AppKit
import SwiftUI

struct IntroView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: CalendarModel
    @ObservedObject var mail: MailModel
    @AppStorage("introWeatherSkipped") private var weatherSkipped = false
    @AppStorage("introMailSkipped") private var mailSkipped = false
    @AppStorage("introInvitationsSkipped") private var invitationsSkipped = false
    @AppStorage("introInvitationsAllowed") private var invitationsAllowed = false
    @State private var locationPending = false
    @State private var invitationPending = false
    @State private var invitationError = ""
    private var isDark: Bool { colorScheme == .dark }
    private var accent: Color {
        isDark ? Color(red: 1, green: 0.40, blue: 0.19) : Color(red: 0.72, green: 0.23, blue: 0.07)
    }
    private var canvas: Color {
        isDark ? Color(red: 0.065, green: 0.06, blue: 0.06) : Color(red: 0.97, green: 0.95, blue: 0.91)
    }
    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "Today", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSApplication.shared.applicationIconImage
    }

    private var calendarReady: Bool { model.connected && model.calendars.contains { model.selected.contains($0.calendarIdentifier) } }
    private var weatherReady: Bool { model.extras.locationAuthorized || weatherSkipped }
    private var mailReady: Bool { (mail.enabled && mail.snapshot.updatedAt != nil && mail.snapshot.status == nil) || mailSkipped }
    private var invitesReady: Bool { invitationsAllowed || invitationsSkipped }
    private var completed: Int { [calendarReady, weatherReady, mailReady, invitesReady].filter { $0 }.count }

    var body: some View {
        ZStack {
            canvas
            RadialGradient(colors: [accent.opacity(isDark ? 0.23 : 0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 850)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 18) {
                        Image(nsImage: appIcon)
                            .resizable().frame(width: 80, height: 80)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("WELCOME TO TODAY").font(.system(size: 10, weight: .bold)).tracking(3).foregroundStyle(accent)
                            Text("A little setup. A clearer day.").font(.system(size: 32, weight: .bold))
                            Text("Your calendar, inbox, and tasks. Together on your Mac.").foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Before you begin", systemImage: "info.circle").font(.headline)
                        Text("Today reads meetings and email from the Apple apps on this Mac. Connect Asana separately in Settings for assigned tasks and parent briefs.")
                        ViewThatFits(in: .horizontal) {
                            HStack { setupButtons }
                            VStack(alignment: .leading) { setupButtons }
                        }
                        Text("Meetings must appear in Apple Calendar and email in Apple Mail. A direct Asana connection does not require a task calendar subscription.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .background(accent.opacity(isDark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.25)))
                    HStack {
                        Text("Let’s get you connected").font(.headline)
                        Spacer()
                        if model.requesting || mail.busy || invitationPending || (locationPending && !weatherReady && !model.extras.locationDenied) {
                            ProgressView().controlSize(.small)
                        }
                        Text("\(completed) of 4 ready").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(completed), total: 4).tint(accent)
                    VStack(spacing: 12) {
                        step("Calendar", subtitle: "See your day using the calendars already synced to this Mac.", ready: calendarReady, skipped: false, enabled: true) {
                            if model.connected {
                                if model.calendars.isEmpty { Text("No calendars found. Add an account in Apple Calendar, then return here.").font(.caption) }
                                TextField("Your first name", text: $model.name).textFieldStyle(.roundedBorder)
                                Picker("Primary calendar", selection: $model.primary) {
                                    Text("Choose your calendar…").tag("")
                                    ForEach(model.calendars, id: \.calendarIdentifier) { item in
                                        Text("\(item.title) — \(item.source.title)").tag(item.calendarIdentifier)
                                    }
                                }
                                Text("Add other calendars later in Settings.").font(.caption).foregroundStyle(.secondary)
                            } else {
                                HStack {
                                    Button(model.requesting ? "Waiting for permission…" : "Allow Calendar") { model.connect() }.disabled(model.requesting)
                                    Button("Open Settings") { openPrivacy("Calendars") }
                                }
                                Text(model.message).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        step("Local weather", subtitle: "Allow location for your forecast. Only approximate coordinates go to the weather service.", ready: weatherReady, skipped: weatherSkipped && !model.extras.locationAuthorized, enabled: calendarReady) {
                            HStack {
                                Button(model.extras.locationDenied ? "Open Location Settings" : locationPending ? "Waiting for permission…" : "Allow Location") {
                                    if model.extras.locationDenied { openPrivacy("LocationServices") }
                                    else { locationPending = true; model.extras.requestLocationAccess() }
                                }.disabled(locationPending && !model.extras.locationDenied)
                                Button("Skip weather") { weatherSkipped = true }
                            }
                            if model.extras.locationDenied { Text("Location wasn’t allowed. Enable it in Settings, or skip weather.").font(.caption) }
                        }
                        step("Apple Mail", subtitle: "Read today’s emails from a mailbox you choose. Today won’t send messages.", ready: mailReady, skipped: mailSkipped, enabled: calendarReady && weatherReady) {
                            MailSettingsView(mail: mail)
                            Button("Skip Mail") { mail.disconnect(); mailSkipped = true }.disabled(mail.busy)
                        }
                        step("Calendar invitations", subtitle: "Let Today open invitations in Calendar so you can respond there.", ready: invitesReady, skipped: invitationsSkipped && !invitationsAllowed, enabled: calendarReady && weatherReady && mailReady) {
                            HStack {
                                Button(invitationPending ? "Waiting for permission…" : "Allow Calendar automation") { requestInvitations() }.disabled(invitationPending)
                                Button("Skip for now") { invitationsSkipped = true }.disabled(invitationPending)
                            }
                            if !invitationError.isEmpty {
                                Text(invitationError).font(.caption)
                                Button("Open Automation Settings") { openPrivacy("Automation") }
                            }
                        }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(completed == 4 ? "You’re ready for Today." : "When macOS asks, choose Allow.").font(.headline)
                            Text("Your calendar and mail stay on this Mac.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open my dashboard") { model.refresh(); if !model.script.isEmpty { model.finishSetup() } }
                            .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
                            .disabled(completed != 4 || mail.busy || invitationPending || model.requesting)
                    }
                }.padding(32).frame(maxWidth: 760)
                    .background(Color.white.opacity(isDark ? 0.035 : 0.65), in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                    .padding(32).frame(maxWidth: .infinity)
            }
        }.foregroundStyle(.primary)
        .onChange(of: model.primary) { _, value in
            guard !value.isEmpty else { return }
            model.selected.insert(value)
            model.refresh()
        }
    }

    private func step<Content: View>(_ title: String, subtitle: String, ready: Bool, skipped: Bool, enabled: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: ready ? (skipped ? "minus.circle.fill" : "checkmark.circle.fill") : "circle")
                .font(.system(size: 22)).foregroundStyle(ready && !skipped ? Color.green : accent)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    if ready { Text(skipped ? "Skipped" : "Connected").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                }
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                if !ready && enabled { content().controlSize(.regular) }
                if ready && skipped {
                    Button("Set up instead") {
                        if title == "Local weather" { weatherSkipped = false; locationPending = false }
                        if title == "Apple Mail" { mailSkipped = false }
                        if title == "Calendar invitations" { invitationsSkipped = false }
                    }.font(.caption)
                }
            }
        }.padding(16).background(isDark ? Color.white.opacity(enabled ? 0.055 : 0.02) : Color.black.opacity(enabled ? 0.035 : 0.015), in: RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? 1 : 0.75)
    }

    @ViewBuilder private var setupButtons: some View {
        ForEach(ConnectionGuide.allCases, id: \.self) { guide in
            Button("Set up \(guide.rawValue)") { ConnectionGuideWindow.shared.show(guide) }
                .buttonStyle(.bordered)
        }
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") { NSWorkspace.shared.open(url) }
    }
    private func requestInvitations() {
        invitationPending = true
        invitationError = ""
        Task {
            defer { invitationPending = false }
            do {
                _ = try await runLocalAutomation(resource: "authorize-calendar", arguments: [])
                invitationsAllowed = true
            } catch { invitationError = "Calendar automation wasn’t connected. Allow Today in Automation settings, then retry, or skip for now." }
        }
    }
}

// A separate utility panel stays visible while the user works in Mail or Calendar.
private enum ConnectionGuide: String, CaseIterable {
    case gmail = "Gmail", calendar = "Google Calendar", asana = "Asana"
    var steps: [String] {
        switch self {
        case .gmail: return [
            "Open Apple Mail. Choose Mail → Add Account, select Google, and continue through Google’s sign-in. If the account is already added, enable Mail for it in System Settings → Internet Accounts.",
            "Let Mail sync, then check that your work inbox and messages appear.",
            "Return to Today’s Apple Mail setup. Click Connect / reload mailboxes, choose your work inbox, then Use mailbox. Allow access to Mail when macOS asks."
        ]
        case .calendar: return [
            "Open Apple Calendar. In Calendar → Settings (or Preferences) → Accounts, click + and choose Google. Sign in to your work account. If it’s already added, enable Calendars in System Settings → Internet Accounts.",
            "Wait for your calendars and events to appear in Apple Calendar. For missing shared calendars, use Google’s Calendar sync page linked below, select the calendars, then refresh Apple Calendar.",
            "Return to Today and choose Allow Calendar. Pick your primary calendar. You can select additional calendars in Today’s Settings → Calendars."
        ]
        case .asana: return [
            "Open Today’s Settings → Calendars → Asana and click Connect Asana.",
            "Sign in with your own Asana account and approve access to tasks, comments, and coworkers. If your organization requires approval, request it from your Asana administrator.",
            "Choose your workspace. Today loads your incomplete assigned tasks with due dates for today and the next two weeks; tasks due today appear in Today’s schedule.",
            "Click View brief on a task to read its parent’s instructions, view comments, and post replies. Type @ and select a coworker to tag them. Complete and edit tasks in Asana.",
            "No Asana calendar subscription is needed. Your meetings still come from the calendars you select in Apple Calendar."
        ]
        }
    }
    var note: String {
        self == .asana ? "Direct Asana tasks and briefs stay on this Mac. Meetings and email still use Apple Calendar and Apple Mail." : "Today reads the Apple apps on this Mac. Signing in happens with Google, not inside Today."
    }
    var helpURL: URL {
        URL(string: self == .gmail ? "https://support.apple.com/kb/ht5361" : self == .calendar ? "https://support.google.com/calendar/answer/99358" : "https://help.asana.com/s/article/calendars-and-asana")!
    }
}

@MainActor private final class ConnectionGuideWindow {
    static let shared = ConnectionGuideWindow()
    private var panel: NSPanel?
    func show(_ guide: ConnectionGuide) {
        let window: NSPanel
        if let panel { window = panel } else {
            window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 570), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.minSize = NSSize(width: 360, height: 400)
            window.center()
            panel = window
        }
        window.title = "Set up \(guide.rawValue)"
        window.contentView = NSHostingView(rootView: ConnectionGuideView(guide: guide, close: { [weak window] in window?.close() }))
        window.makeKeyAndOrderFront(nil)
    }
}

private struct ConnectionGuideView: View {
    let guide: ConnectionGuide
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up \(guide.rawValue)").font(.title2.bold())
                    Text("Keep this guide beside you as you set up.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.accessibilityLabel("Close setup guide")
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.orange)
                            Text(text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(guide.note).font(.callout).foregroundStyle(.secondary)
                    Link("Official setup instructions ↗", destination: guide.helpURL)
                    if guide == .calendar {
                        Link("Choose Google calendars to sync ↗", destination: URL(string: "https://www.google.com/calendar/syncselect")!)
                    }
                }.padding(20)
            }
            Divider()
            HStack {
                Button(guide == .gmail ? "Open Apple Mail" : guide == .asana ? "Open Asana" : "Open Apple Calendar") {
                    if guide == .asana {
                        NSWorkspace.shared.open(URL(string: "https://app.asana.com/")!)
                        return
                    }
                    let identifier = guide == .gmail ? "com.apple.mail" : "com.apple.iCal"
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
                Spacer()
                Button("Done", action: close).keyboardShortcut(.cancelAction)
            }.padding(16)
        }.frame(minWidth: 320, minHeight: 360)
    }
}
