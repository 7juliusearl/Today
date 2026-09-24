import AppKit
import SwiftUI
import EventKit
import WebKit
import Combine
import ServiceManagement

@MainActor final class CalendarModel: ObservableObject {
    let store = EKEventStore()
    let extras = DashboardExtras()
    let login = LoginSettings()
    let mail = MailModel()
    let asanaBriefs = AsanaBriefs()
    let companion = CompanionServer()
    private var pendingInvitations: [String: EKEvent] = [:]
    private var calendarActions: [String: String] = [:]
    private var automaticRefresh: AutoRefreshController?
    @Published var calendars: [EKCalendar] = []
    @Published var selected: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "selectedCalendars") ?? [])
    @Published var name: String = UserDefaults.standard.string(forKey: "firstName") ?? ""
    @Published var primary: String = UserDefaults.standard.string(forKey: "primaryCalendar") ?? ""
    @Published var asanaCalendar = UserDefaults.standard.string(forKey: "asanaCalendar") ?? ""
    @Published var message = "Connect to the calendars already synced with Apple Calendar."
    @Published var script = "" { didSet { if script.isEmpty { companion.snapshot = "" } } }
    @Published var revision = 0
    @Published var connected = false
    @Published var requesting = false
    @Published var calendarAuthorization = EKEventStore.authorizationStatus(for: .event)
    @Published var calendarMessage = ""
    @Published var setupCompleted = UserDefaults.standard.bool(forKey: "introCompleted")
    func finishSetup() {
        setupCompleted = true
        UserDefaults.standard.set(true, forKey: "introCompleted")
        refresh()
    }

    init() {
        if companion.resumeOnLaunch { companion.start() }
        automaticRefresh = AutoRefreshController { [weak self] in
            guard let self, (self.connected || self.asanaBriefs.auth.connected) else { return }
            self.refresh()
        }
        asanaBriefs.onChange = { [weak self] in self?.objectWillChange.send(); self?.refresh() }
        if asanaBriefs.auth.connected { asanaBriefs.auth.reloadWorkspaces() }
        mail.onChange = { [weak self] in
            guard let self, (self.connected || self.asanaBriefs.auth.connected) else { return }
            self.refresh()
        }
        extras.onChange = { [weak self] in
            self?.objectWillChange.send()
            guard let self, (self.connected || self.asanaBriefs.auth.connected) else { return }
            self.refresh()
        }
    }

    func respondInCalendar(id: String) {
        guard let event = pendingInvitations[id], calendarActions[id] != "Opening Calendar…" else { return }
        struct Target: Encodable { let uid: String; let calendar: String; let start: String }
        let target = Target(uid: event.calendarItemExternalIdentifier ?? "", calendar: event.calendar.title,
                            start: ISO8601DateFormatter().string(from: event.startDate))
        calendarActions[id] = "Opening Calendar…"
        refresh()
        Task {
            do {
                let input = String(decoding: try JSONEncoder().encode(target), as: UTF8.self)
                let data = try await runLocalAutomation(resource: "open-calendar", arguments: [input])
                struct Result: Decodable { let found: Bool }
                let result = try JSONDecoder().decode(Result.self, from: data)
                calendarActions[id] = result.found ? "Use Accept, Maybe, or Decline in Calendar."
                    : "Calendar is open on the event’s date. Use its Invitations inbox to respond."
            } catch {
                calendarActions[id] = "Could not reveal the event. Allow Today under Privacy & Security → Automation → Calendar, or open Calendar’s Invitations inbox."
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                    _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            refresh()
        }
    }

    func connect() {
        requesting = true
        store.requestFullAccessToEvents { granted, error in
            Task { @MainActor in
                self.requesting = false
                self.calendarAuthorization = EKEventStore.authorizationStatus(for: .event)
                if granted { self.store.reset(); self.loadCalendars(); self.refresh() }
                else {
                    self.loadCalendars()
                    self.message = self.calendarMessage
                }
            }
        }
    }
    func loadCalendars() {
        calendarAuthorization = EKEventStore.authorizationStatus(for: .event)
        guard calendarAuthorization == .fullAccess else {
            connected = false; calendars = []
            calendarMessage = calendarAuthorization == .denied || calendarAuthorization == .restricted
                ? "Calendar access is off. Enable Today in System Settings → Privacy & Security → Calendars. Asana connects separately."
                : "Allow Today to read Apple Calendar so your meetings and calendar choices can appear. Asana connects separately."
            return
        }
        calendars = store.calendars(for: .event).sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
        connected = true
        calendarMessage = calendars.isEmpty ? "No calendars found in Apple Calendar. Check that your Google account’s Calendars option is enabled on this Mac, then reload." : ""
    }
    func reloadCalendars() {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { store.reset() }
        loadCalendars()
        refresh()
    }
    func refresh() {
        loadCalendars()
        let chosen = calendars.filter { selected.contains($0.calendarIdentifier) }
        UserDefaults.standard.set(Array(selected), forKey: "selectedCalendars")
        UserDefaults.standard.set(name, forKey: "firstName")
        UserDefaults.standard.set(primary, forKey: "primaryCalendar")
        UserDefaults.standard.set(asanaCalendar, forKey: "asanaCalendar")
        extras.refresh()
        if setupCompleted { mail.refresh() }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 91, to: start)!
        let events = chosen.isEmpty ? [] : store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: chosen))
        let calendar = calendarPayload(events.filter { $0.calendar.calendarIdentifier != asanaCalendar }, now: now, primary: primary)
        let asanaSource = calendars.first { $0.calendarIdentifier == asanaCalendar }
        let asanaEvents = asanaSource.map { source in
            store.events(matching: store.predicateForEvents(withStart: start,
                end: Calendar.current.date(byAdding: .day, value: 15, to: start)!, calendars: [source]))
        } ?? []
        let calendarAsana = asanaPayload(asanaEvents, now: now, calendarName: asanaSource?.title)
        asanaBriefs.refresh(calendarAsana.tasks, source: asanaCalendar)
        let directTasks = asanaBriefs.directTasks
        let asana = AsanaPayload(connected: directTasks != nil || calendarAsana.connected, calendarName: directTasks != nil ? "Asana · My tasks" : calendarAsana.calendarName,
            tasks: (directTasks ?? calendarAsana.tasks).map { task in
                var task = task; task.brief = asanaBriefs.brief(for: task.url); return task
            })
        pendingInvitations = [:]
        let pendingIDs = Set(calendar.pendingInvites.map(\.id))
        for event in events {
            let id = (event.eventIdentifier ?? event.calendarItemIdentifier) + "@" + ISO8601DateFormatter().string(from: event.startDate)
            if pendingIDs.contains(id) { pendingInvitations[id] = event }
        }
        struct Dashboard: Encodable {
            let generatedAt: String
            let userFirstName: String
            let calendar: CalendarPayload
            let asana: AsanaPayload
            let verse: DashboardExtras.Verse
            let weather: DashboardExtras.Weather
            let mail: MailSnapshot
            let calendarActions: [String: String]
        }
        do {
            let data = try JSONEncoder().encode(Dashboard(generatedAt: ISO8601DateFormatter().string(from: now),
                userFirstName: name.isEmpty ? "there" : name, calendar: calendar, asana: asana, verse: extras.verse, weather: extras.weather, mail: mail.snapshot, calendarActions: calendarActions))
            let sharedData = try JSONEncoder().encode(Dashboard(generatedAt: ISO8601DateFormatter().string(from: now),
                userFirstName: name.isEmpty ? "there" : name, calendar: calendar, asana: calendarAsana, verse: extras.verse, weather: extras.weather, mail: mail.snapshot, calendarActions: calendarActions))
            companion.snapshot = "window.LOCAL_CALENDAR_PROTOTYPE = true; window.DASHBOARD_DATA = " + String(decoding: sharedData, as: UTF8.self) + ";"
            script = "window.LOCAL_CALENDAR_PROTOTYPE = true; window.DASHBOARD_DATA = " + String(decoding: data, as: UTF8.self) + ";"
            // Load only the two explicitly supported personal files, without bundling them.
            if let directory = TodayPaths.personalData {
                for filename in ["schedule.js", "plan.js"] {
                    let url = directory.appendingPathComponent(filename)
                    if let source = try? String(contentsOf: url, encoding: .utf8) {
                        script += "\n;try {\n" + source + "\n} catch (_) {}\n"
                        companion.snapshot += "\n;try {\n" + source + "\n} catch (_) {}\n"
                    }
                }
            }
            revision += 1
            message = "Read Apple Calendar at \(now.formatted(date: .omitted, time: .shortened)). Google sync is managed by Apple Calendar."
        } catch { message = "Could not prepare calendar data: \(error.localizedDescription)" }
    }
}

struct DashboardWebView: NSViewRepresentable {
    @ObservedObject var model: CalendarModel
    var pinned = false
    var updateAvailable = false
    var spaceWarning = false
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "dashboardControl")
        configuration.userContentController.add(context.coordinator, name: "calendarRefresh")
        configuration.userContentController.add(context.coordinator, name: "openSettings")
        configuration.userContentController.add(context.coordinator, name: "mailOpen")
        configuration.userContentController.add(context.coordinator, name: "mailOpenApp")
        configuration.userContentController.add(context.coordinator, name: "respondInCalendar")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "asanaComments")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.controlsScript = "window.todayNativeState?.({pinned: \(pinned), updateAvailable: \(updateAvailable), spaceWarning: \(spaceWarning)});"
        context.coordinator.updateControls(in: view)
        guard context.coordinator.revision != model.revision else { return }
        context.coordinator.revision = model.revision
        context.coordinator.update(model.script, in: view)
    }
    class Coordinator: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        let model: CalendarModel
        var revision = -1
        var controlsScript = ""
        func updateControls(in view: WKWebView) {
            if ready { view.evaluateJavaScript(controlsScript, completionHandler: nil) }
        }
        private var started = false
        private var ready = false
        private var applying = false
        private var pendingScript: String?

        func update(_ script: String, in view: WKWebView) {
            if !started {
                started = true
                view.configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                let root = TodayPaths.dashboard
                view.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root.deletingLastPathComponent())
                return
            }
            pendingScript = script
            applyPending(in: view)
        }
        private func applyPending(in view: WKWebView) {
            guard ready, !applying, let script = pendingScript else { return }
            pendingScript = nil
            applying = true
            view.evaluateJavaScript(script + "\nwindow.refreshLocalDashboard();") { [weak self, weak view] _, error in
                guard let self, let view else { return }
                self.applying = false
                if error != nil { self.model.message = "Could not update the dashboard. Try Refresh again." }
                self.applyPending(in: view)
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            updateControls(in: webView)
            applyPending(in: webView)
        }
        init(_ model: CalendarModel) { self.model = model }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard message.name == "asanaComments", message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.isFileURL == true,
                  let body = message.body as? [String: Any], let url = body["taskURL"] as? String,
                  let parent = body["parent"] as? Bool, let action = body["action"] as? String,
                  ["load", "post", "people"].contains(action), action != "post" || body["text"] is String else {
                replyHandler(nil, "Invalid comment request."); return
            }
            Task { @MainActor in
                do {
                    let result: [String: Any]
                    if action == "people" { result = try await model.asanaBriefs.users(taskURL: url) }
                    else {
                        result = try await model.asanaBriefs.comments(taskURL: url, parent: parent,
                            text: action == "post" ? body["text"] as? String : nil, offset: body["offset"] as? String,
                            mentions: body["mentions"] as? [[String: Any]] ?? [])
                    }
                    replyHandler(result, nil)
                } catch { replyHandler(nil, error.localizedDescription) }
            }
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true else { return }
            if message.name == "dashboardControl", let action = message.body as? String {
                if ["dark", "light"].contains(action) {
                    UserDefaults.standard.set(action, forKey: "dashboardAppearance")
                    NSApp.appearance = NSAppearance(named: action == "dark" ? .darkAqua : .aqua)
                } else if ["pin", "options"].contains(action) {
                    NotificationCenter.default.post(name: Notification.Name("TodayDashboardControl"), object: action)
                }
            } else if message.name == "openSettings" {
                NotificationCenter.default.post(name: Notification.Name("TodayOpenSettings"), object: nil)
            } else if message.name == "respondInCalendar", let id = message.body as? String {
                model.respondInCalendar(id: id)
            } else if message.name == "mailOpenApp" {
                model.mail.openMailApp()
            } else if message.name == "mailOpen", let id = message.body as? String {
                model.mail.openMessage(id: id)
            } else if message.name == "calendarRefresh" {
                model.mail.refresh(force: true)
                model.refresh()
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.isFileURL { decisionHandler(.allow); return }
            if navigationAction.navigationType == .linkActivated && ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
}

struct CalendarSettingsView: View {
    @ObservedObject var model: CalendarModel
    @ObservedObject var login: LoginSettings
    @Environment(\.dismiss) var dismiss
    @State private var selected: Set<String> = []
    @State private var name = ""
    @State private var primary = ""
    @State private var asanaCalendar = ""

    private enum Page: String, CaseIterable {
        case general = "General", calendars = "Calendars", mail = "Mail", weather = "Weather", ipad = "Devices", updates = "Updates"
    }
    @State private var page: Page = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings").font(.title2.weight(.bold))
                    Text("Make Today yours.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28)
                }.buttonStyle(.borderless).background(.quaternary, in: Circle())
                    .accessibilityLabel("Close settings without saving name or calendar changes")
                    .help("Close settings")
            }.padding(22)
            Picker("Settings section", selection: $page) {
                ForEach(Page.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 22).padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch page {
                    case .general:
                        settingsCard {
                            Text("Your profile").font(.headline)
                            TextField("First name", text: $name).textFieldStyle(.roundedBorder)
                            Text("Used in your dashboard greeting.").font(.caption).foregroundStyle(.secondary)
                        }
                        settingsCard {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at login", isOn: Binding(
                    get: { login.enabled }, set: { login.setEnabled($0) }
                ))
                Text(login.explanation).font(.caption).foregroundStyle(.secondary)
                Text("This switch takes effect immediately.").font(.caption).foregroundStyle(.secondary)
                if login.status == .requiresApproval {
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = login.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
                        }
                        settingsCard {
            if let project = TodayPaths.project {
                Button("Open customization folder") { NSWorkspace.shared.open(project) }
                Text("Open this folder in Codex or Claude to customize Today. Restart Today after layout edits; schedule and plan edits appear on refresh.")
                    .font(.caption).foregroundStyle(.secondary)
            }
                            if TodayPaths.project == nil {
                                Text("Personalize your dashboard").font(.headline)
                                Text("Use the timer’s gear to choose which sections stay visible while you focus. Edit the project folder with Codex or Claude for other customizations.").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    case .calendars:
                        settingsCard {
                            Text("Your calendars").font(.headline)
                            Text("Choose which calendars appear on your dashboard.").foregroundStyle(.secondary)
                            if !model.calendarMessage.isEmpty {
                                Text(model.calendarMessage).font(.callout).foregroundStyle(.secondary)
                            }
                            HStack {
                                if model.calendarAuthorization != .fullAccess {
                                    Button(model.requesting ? "Connecting…" : "Connect calendars") { model.connect() }.disabled(model.requesting)
                                    Button("Calendar privacy settings") {
                                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                                    }
                                }
                                Button("Reload calendars") { model.reloadCalendars() }
                                if model.calendars.isEmpty {
                                    Button("Open Apple Calendar") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
                                }
                            }
                            if !model.calendars.isEmpty {
            Picker("Primary calendar", selection: $primary) {
                Text("Choose…").tag("")
                ForEach(model.calendars, id: \.calendarIdentifier) { calendar in
                    Text("\(calendar.title) — \(calendar.source.title)").tag(calendar.calendarIdentifier)
                }
            }
            Text("Calendars to display").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: Binding(
                            get: { selected.contains(calendar.calendarIdentifier) },
                            set: { if $0 { selected.insert(calendar.calendarIdentifier) } else { selected.remove(calendar.calendarIdentifier) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(calendar.title)
                                Text(calendar.source.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkbox)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                            }
            Text("Google syncing is handled by Apple Calendar. Today only reads events. Optional device sharing is controlled separately.")
                .font(.callout).foregroundStyle(.secondary)
                        }
                        settingsCard {
                            Text("Asana").font(.headline)
                            Text("Connect to see your assigned tasks, due dates, and parent briefs. No Asana calendar subscription is needed. Meetings still come from Apple Calendar.").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(model.asanaBriefs.auth.connected ? "Reconnect Asana" : "Connect Asana") { model.asanaBriefs.auth.connect() }
                                    .disabled(model.asanaBriefs.auth.busy)
                                if model.asanaBriefs.auth.connected {
                                    Button("Disconnect") { model.asanaBriefs.auth.disconnect() }.disabled(model.asanaBriefs.auth.busy)
                                    Button("Reload workspaces") { model.asanaBriefs.auth.reloadWorkspaces() }.disabled(model.asanaBriefs.auth.busy)
                                }
                            }
                            Text(model.asanaBriefs.auth.message).font(.caption).foregroundStyle(.secondary)
                            Text("To enable comments on an existing connection, choose Reconnect Asana and approve comment access. Today posts only when you press Post comment.").font(.caption).foregroundStyle(.secondary)
                            if model.asanaBriefs.auth.connected {
                                Picker("Workspace", selection: Binding(get: { model.asanaBriefs.workspace }, set: { model.asanaBriefs.setWorkspace($0) })) {
                                    Text("Choose a workspace").tag("")
                                    ForEach(model.asanaBriefs.auth.workspaces, id: \.gid) { Text($0.name).tag($0.gid) }
                                }
                                Toggle("Show Asana tasks and parent briefs", isOn: Binding(get: { model.asanaBriefs.enabled }, set: { model.asanaBriefs.setEnabled($0) }))
                                Text(model.asanaBriefs.status).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Direct Asana tasks and briefs stay on this Mac and are excluded from device sharing.").font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Optional calendar subscription fallback") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Asana tasks").font(.headline)
                Text("In Asana, click the small down arrow beside My tasks → Sync/Export → Google Calendar (recommended). Follow the steps to add it to your work Google Calendar. Make sure that task calendar also appears in Apple Calendar on this Mac, then reload and choose it below.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Asana calendar", selection: $asanaCalendar) {
                    Text("Not connected").tag("")
                    ForEach(model.calendars, id: \.calendarIdentifier) { calendar in
                        Text("\(calendar.title) — \(calendar.source.title)").tag(calendar.calendarIdentifier)
                    }
                }
                HStack {
                    Button("Reload calendars") { model.loadCalendars() }
                    Link("Setup guide ↗", destination: URL(string: "https://asana.com/apps/calendar")!)
                }
                Text("Tasks due today appear in Today’s calendar. Subscription updates may be delayed. Complete tasks in Asana; tasks without due dates aren’t included.")
                    .font(.caption).foregroundStyle(.secondary)
            }
                            }
                        }
                    case .mail:
                        settingsCard { MailSettingsView(mail: model.mail) }
                    case .weather:
                        settingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weather").font(.headline)
                Label(model.extras.locationAuthorized ? "Location access allowed" : model.extras.locationDenied ? "Location access is off" : "Location not connected",
                      systemImage: model.extras.locationAuthorized ? "checkmark.circle.fill" : "location.slash")
                    .foregroundStyle(model.extras.locationAuthorized ? Color.green : Color.secondary)
                Text("Today uses your Mac’s location for local weather. Only approximate coordinates are sent to the weather service.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if !model.extras.locationAuthorized && !model.extras.locationDenied {
                        Button("Enable location") {
                            UserDefaults.standard.set(false, forKey: "introWeatherSkipped")
                            model.extras.requestLocationAccess()
                        }
                    }
                    Button("Open Location Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    if model.extras.locationAuthorized {
                        Button(model.extras.weatherBusy ? "Updating…" : "Refresh weather") { model.extras.retryWeather() }
                            .disabled(model.extras.weatherBusy)
                    }
                }
                if model.extras.locationDenied {
                    Text("Enable Location Services and allow Today in macOS Settings, then return here.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if model.extras.locationAuthorized {
                    Text(model.extras.weather.message.isEmpty ? "Local forecast is up to date." : model.extras.weather.message)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
                        }
                    case .ipad:
                        settingsCard { CompanionSettingsView(server: model.companion) }
                    case .updates:
                        settingsCard { TodayUpdateSettings() }
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }.id(page).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Save applies your name and calendar choices. Other controls apply immediately.")
                    .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(selected.count) selected").foregroundStyle(.secondary)
                Button("Save") {
                    model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.primary = primary
                    model.asanaCalendar = asanaCalendar
                    model.selected = selected
                    model.refresh()
                    if !model.script.isEmpty { dismiss() }
                }.keyboardShortcut(.defaultAction)
                    .disabled(model.requesting)
            }
            }.padding(.horizontal, 22).padding(.vertical, 16)
        }
        .tint(Color(red: 0.93, green: 0.29, blue: 0.13))
        .frame(width: min(680, (NSScreen.main?.visibleFrame.width ?? 1000) - 60),
               height: min(700, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
        .onAppear {
            login.reload()
            model.loadCalendars()
            selected = model.selected
            name = model.name
            primary = model.primary
            asanaCalendar = model.asanaCalendar
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.reload()
            model.reloadCalendars()
            model.objectWillChange.send()
        }
        .onChange(of: primary) { _, value in
            if !value.isEmpty { selected.insert(value) }
        }
    }
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary, lineWidth: 1))
    }
}

// Resolve this view's own window, including when SwiftUI attaches it after creation.
struct DashboardWindowLevel: NSViewRepresentable {
    var alwaysOnTop: Bool
    @ObservedObject var space: WindowSpaceController

    final class WindowView: NSView {
        private weak var configuredWindow: NSWindow?
        private var originalSpaceBehavior: NSWindow.CollectionBehavior = []
        weak var space: WindowSpaceController?
        var alwaysOnTop = false {
            didSet { applyLevel() }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window, configuredWindow !== window {
                configuredWindow = window
                originalSpaceBehavior = window.collectionBehavior.intersection([.canJoinAllSpaces, .moveToActiveSpace])
                // Restore only on attachment, never during refreshes or live resizing.
                // AppKit saves subsequent moves and resizes under this stable name.
                window.setFrameUsingName("TodayDashboardWindow")
                window.setFrameAutosaveName("TodayDashboardWindow")
            }
            applyLevel()
        }
        private func applyLevel() {
            guard let window else { return }
            space?.window = window
            space?.update(pinned: alwaysOnTop)
            let level: NSWindow.Level = alwaysOnTop ? .floating : .normal
            if window.level != level { window.level = level }
            var behavior = window.collectionBehavior
            behavior.subtract([.canJoinAllSpaces, .moveToActiveSpace])
            behavior.formUnion(alwaysOnTop ? [.canJoinAllSpaces] : originalSpaceBehavior)
            if window.collectionBehavior != behavior { window.collectionBehavior = behavior }
        }
    }

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.space = space
        view.alwaysOnTop = alwaysOnTop
        return view
    }
    func updateNSView(_ view: WindowView, context: Context) {
        view.space = space
        view.alwaysOnTop = alwaysOnTop
    }
}

struct PrototypeView: View {
    @ObservedObject private var updater = TodayUpdater.shared
    @StateObject var model = CalendarModel()
    @StateObject private var space = WindowSpaceController()
    @State private var settingsPresented = false
    @State private var windowControlPresented = false
    @State private var windowOptionsPresented = false
    @State private var setupAfterOptions = false
    @AppStorage("dashboardAppearance") private var dashboardAppearance = ""
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    var body: some View {
        Group {
            if model.setupCompleted && !model.script.isEmpty {
                DashboardWebView(model: model, pinned: alwaysOnTop, updateAvailable: updater.available != nil, spaceWarning: space.enabled && !space.trusted)
            } else {
                IntroView(model: model, mail: model.mail)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(DashboardWindowLevel(alwaysOnTop: alwaysOnTop, space: space))
        .navigationTitle("Today")
        .preferredColorScheme(dashboardAppearance == "dark" ? .dark : dashboardAppearance == "light" ? .light : nil)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TodayDashboardControl"))) { notification in
            switch notification.object as? String {
            case "pin": alwaysOnTop.toggle()
            case "options": space.refreshPermission(); windowOptionsPresented = true
            default: break
            }
        }
        .sheet(isPresented: $windowOptionsPresented, onDismiss: {
            if setupAfterOptions { setupAfterOptions = false; windowControlPresented = true }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Window options").font(.title2.bold())
                    Spacer()
                    Button { windowOptionsPresented = false } label: { Image(systemName: "xmark") }.help("Close window options")
                }
                    Toggle("Reserve dashboard space", isOn: Binding(
                        get: { space.enabled },
                        set: { enabled in
                            space.enabled = enabled
                            if enabled {
                                space.refreshPermission()
                                if !space.trusted { setupAfterOptions = true; windowOptionsPresented = false }
                            }
                        }
                    ))
                    Text("Fits enlarged windows into the largest space beside Today.")
                    if space.enabled && !alwaysOnTop {
                        Text("Paused — turn on Always on top to resume.")
                    }
                    if !space.trusted {
                        Button("Set up window control…") {
                            space.refreshPermission()
                            setupAfterOptions = true; windowOptionsPresented = false
                        }
                    }
                    if !space.status.isEmpty { Text(space.status) }

                HStack { Spacer(); Button("Done") { windowOptionsPresented = false }.keyboardShortcut(.cancelAction) }
            }.padding(24).frame(width: 420)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TodayOpenSettings"))) { _ in model.loadCalendars(); settingsPresented = true }
        .sheet(isPresented: $settingsPresented) { CalendarSettingsView(model: model, login: model.login) }
        .sheet(isPresented: $windowControlPresented) { WindowControlSetupView(space: space) }
        .onAppear {
            updater.checkAutomatically()
            if TodayPaths.portable && TodayPaths.project == nil { TodayPaths.chooseProject() }
            model.refresh()
        }
        .onReceive(timer) { _ in
            updater.checkAutomatically()
            if !settingsPresented { model.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            space.refreshPermission()
            if !settingsPresented { model.refresh() }
        }
    }
}

@main struct TodayCalendarApp: App {
    var body: some Scene {
        WindowGroup { PrototypeView() }.defaultSize(width: 1200, height: 850)
    }
}
