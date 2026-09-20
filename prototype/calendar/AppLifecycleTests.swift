import AppKit
import EventKit
import ServiceManagement

@MainActor final class FakeLoginService: LoginService {
    var status: SMAppService.Status = .notRegistered
    var registrations = 0
    var removals = 0
    var fail = false
    var requireApproval = false
    func register() throws {
        registrations += 1
        if fail { throw NSError(domain: "Test", code: 1) }
        status = requireApproval ? .requiresApproval : .enabled
    }
    func unregister() throws {
        removals += 1
        if fail { throw NSError(domain: "Test", code: 2) }
        status = .notRegistered
    }
}

@main struct AppLifecycleTests {
    @MainActor static func main() async throws {
        let service = FakeLoginService()
        let login = LoginSettings(service: service)
        assert(!login.enabled && service.registrations == 0, "Opening settings must not register the app")
        login.setEnabled(true)
        assert(login.enabled && service.registrations == 1)
        login.setEnabled(true)
        assert(service.registrations == 1, "Do not register twice")
        service.fail = true
        login.setEnabled(false)
        assert(login.enabled && login.error != nil, "Failed removal must preserve actual state")
        service.fail = false
        login.setEnabled(false)
        assert(!login.enabled && login.error == nil)
        service.requireApproval = true
        login.setEnabled(true)
        assert(login.status == .requiresApproval && login.enabled)
        service.status = .notRegistered
        login.reload()
        assert(!login.enabled, "Respect changes made in System Settings")
        service.fail = true
        login.setEnabled(true)
        assert(!login.enabled && login.error != nil, "Registration failure must not look successful")

        let workspace = NotificationCenter()
        let calendar = NotificationCenter()
        var reads = 0
        var controller: AutoRefreshController? = AutoRefreshController(
            workspaceCenter: workspace, calendarCenter: calendar,
            debounceSeconds: 0.02, retryNanoseconds: 300_000_000,
            refresh: { reads += 1 })
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(reads == 1, "Wake must refresh immediately")
        try await Task.sleep(nanoseconds: 300_000_000)
        assert(reads == 2, "Wake must retry after sync resumes")
        for _ in 0..<5 { calendar.post(name: .EKEventStoreChanged, object: nil) }
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(reads == 3, "Calendar change bursts must coalesce")
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        assert(reads == 4)
        controller = nil
        _ = controller
        try await Task.sleep(nanoseconds: 350_000_000)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        calendar.post(name: .EKEventStoreChanged, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        assert(reads == 4, "Removing controller must cancel pending work and observers")
        print("PASS: login enable/disable, approval and failure states, external setting changes, wake refresh/retry, calendar change debounce, observer cleanup. No real login items or calendars were changed.")
    }
}
