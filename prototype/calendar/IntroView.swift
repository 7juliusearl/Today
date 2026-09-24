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
                            Text("Your calendar, inbox, and daily rhythm. Together on your Mac.").foregroundStyle(.secondary)
                        }
                    }
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
