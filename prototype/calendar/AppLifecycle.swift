import AppKit
import Combine
import EventKit
import ServiceManagement

@MainActor protocol LoginService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginService {}

@MainActor final class LoginSettings: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?
    private let service: any LoginService

    init(service: any LoginService = SMAppService.mainApp) {
        self.service = service
        reload()
    }
    var enabled: Bool { status == .enabled || status == .requiresApproval }
    var explanation: String {
        switch status {
        case .enabled: return "Today will open automatically when you sign in to this Mac."
        case .requiresApproval: return "Allow Today in System Settings → General → Login Items to finish enabling this."
        case .notFound: return "macOS could not find this app. Keep it in a fixed location and try again."
        default: return "Open Today automatically when you sign in to this Mac."
        }
    }
    func reload() { status = service.status }
    func setEnabled(_ wanted: Bool) {
        error = nil
        reload()
        do {
            if wanted && !enabled { try service.register() }
            if !wanted && enabled { try service.unregister() }
        } catch {
            self.error = "Could not change launch at login: \(error.localizedDescription)"
        }
        reload() // Display the real system state, including pending approval or failure.
    }
}

// Keep observers alive independently of whether the dashboard or Settings is visible.
@MainActor final class AutoRefreshController {
    private var subscriptions: Set<AnyCancellable> = []
    private var wakeRetry: Task<Void, Never>?
    private let retryNanoseconds: UInt64
    private let refresh: @MainActor () -> Void

    init(workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         calendarCenter: NotificationCenter = .default,
         debounceSeconds: Double = 1,
         retryNanoseconds: UInt64 = 15_000_000_000,
         refresh: @escaping @MainActor () -> Void) {
        self.retryNanoseconds = retryNanoseconds
        self.refresh = refresh
        workspaceCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.didWake() } }
            .store(in: &subscriptions)
        calendarCenter.publisher(for: .EKEventStoreChanged)
            .debounce(for: .seconds(debounceSeconds), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.refresh() } }
            .store(in: &subscriptions)
    }
    private func didWake() {
        refresh()
        wakeRetry?.cancel()
        // Read again after Apple Calendar has had time to resume syncing.
        let delay = retryNanoseconds
        wakeRetry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
    deinit { wakeRetry?.cancel() }
}
