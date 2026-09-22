import AppKit
import ApplicationServices
import Combine
import SwiftUI

enum DashboardSpace {
    // All rectangles use AppKit's bottom-left screen coordinates.
    static func remainingFrame(screen: CGRect, dashboard: CGRect) -> CGRect? {
        let occupied = screen.intersection(dashboard)
        guard !occupied.isNull, !occupied.isEmpty else { return nil }
        let gap: CGFloat = 8
        let candidates = [
            CGRect(x: screen.minX, y: screen.minY, width: max(0, occupied.minX - screen.minX - gap), height: screen.height),
            CGRect(x: occupied.maxX + gap, y: screen.minY, width: max(0, screen.maxX - occupied.maxX - gap), height: screen.height),
            CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: max(0, occupied.minY - screen.minY - gap)),
            CGRect(x: screen.minX, y: occupied.maxY + gap, width: screen.width, height: max(0, screen.maxY - occupied.maxY - gap))
        ]
        return candidates.filter { $0.width >= 320 && $0.height >= 240 }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    static func isFilled(_ frame: CGRect, screen: CGRect) -> Bool {
        let tolerance: CGFloat = 18 // Allow macOS tiling margins.
        return abs(frame.minX - screen.minX) <= tolerance && abs(frame.minY - screen.minY) <= tolerance
            && abs(frame.maxX - screen.maxX) <= tolerance && abs(frame.maxY - screen.maxY) <= tolerance
    }

    static func flip(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }
}

@MainActor final class WindowSpaceController: ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey: "reserveDashboardSpace") {
        didSet { UserDefaults.standard.set(enabled, forKey: "reserveDashboardSpace") }
    }
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var status = ""
    weak var window: NSWindow?
    private var timer: Timer?
    private var lastAttemptedWindow: AXUIElement?
    private var lastAttemptedFrame: CGRect?
    private var pendingWindow: AXUIElement?
    private var pendingFrame: CGRect?

    func update(pinned: Bool) {
        let active = enabled && pinned
        if active && timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkFrontWindow() }
            }
        } else if !active {
            timer?.invalidate()
            timer = nil
            resetAttempt()
        }
    }

    func requestAccess() {
        // The system dialog owns its Open System Settings action. Opening the
        // pane ourselves here creates two competing windows for the same request.
        trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    func openPermissionSettings() {
        refreshPermission()
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshPermission() {
        let allowed = AXIsProcessTrusted()
        if trusted != allowed {
            trusted = allowed
            resetAttempt()
            status = ""
        }
    }

    private func resetAttempt() {
        pendingWindow = nil
        pendingFrame = nil
        lastAttemptedWindow = nil
        lastAttemptedFrame = nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func checkFrontWindow() {
        refreshPermission()
        guard trusted else {
            status = "Waiting for approval. Choose Set up window control to continue."
            resetAttempt()
            return
        }
        guard let window, window.isVisible, !window.isMiniaturized, window.isOnActiveSpace,
              !window.styleMask.contains(.fullScreen), !window.inLiveResize,
              NSEvent.pressedMouseButtons == 0 else { resetAttempt(); return }
        guard let screen = window.screen, let primary = NSScreen.screens.first,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { resetAttempt(); return }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let raw = attribute(application, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { resetAttempt(); return }
        let target = unsafeBitCast(raw, to: AXUIElement.self)
        guard attribute(target, "AXFullScreen") as? Bool != true,
              attribute(target, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              let rawPosition = attribute(target, kAXPositionAttribute), CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              let rawSize = attribute(target, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { resetAttempt(); return }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(rawPosition, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &size) else { return }
        let frame = DashboardSpace.flip(CGRect(origin: position, size: size), primaryTop: primary.frame.maxY)
        guard DashboardSpace.isFilled(frame, screen: screen.visibleFrame) else { resetAttempt(); return }
        // Require a settled frame across two checks; never fight a drag or animation.
        guard let pendingWindow, CFEqual(pendingWindow, target), pendingFrame == frame else {
            self.pendingWindow = target
            pendingFrame = frame
            return
        }
        if let lastAttemptedWindow, CFEqual(lastAttemptedWindow, target), lastAttemptedFrame == frame { return }
        lastAttemptedWindow = target
        lastAttemptedFrame = frame
        guard let remaining = DashboardSpace.remainingFrame(screen: screen.visibleFrame, dashboard: window.frame) else {
            status = "Make Today smaller or move it toward an edge to leave room for another app."
            return
        }
        var canMove = DarwinBoolean(false)
        var canResize = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(target, kAXPositionAttribute as CFString, &canMove) == .success, canMove.boolValue,
              AXUIElementIsAttributeSettable(target, kAXSizeAttribute as CFString, &canResize) == .success, canResize.boolValue else {
            status = "This app does not allow its window to be resized."
            return
        }
        let desired = DashboardSpace.flip(remaining, primaryTop: primary.frame.maxY)
        var newPosition = desired.origin
        var newSize = desired.size
        guard let sizeValue = AXValueCreate(.cgSize, &newSize), let positionValue = AXValueCreate(.cgPoint, &newPosition) else { return }
        let resized = AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, sizeValue)
        guard resized == .success else { status = "This app could not be resized."; return }
        let moved = AXUIElementSetAttributeValue(target, kAXPositionAttribute as CFString, positionValue)
        guard moved == .success else { status = "This app could not be moved beside Today."; return }
        // An app can report success while clamping to its own minimum size.
        if let actualSize = attribute(target, kAXSizeAttribute), CFGetTypeID(actualSize) == AXValueGetTypeID(),
           AXValueGetValue(unsafeBitCast(actualSize, to: AXValue.self), .cgSize, &size),
           size.width > newSize.width + 2 || size.height > newSize.height + 2 {
            status = "This app needs more room. Make Today smaller, then enlarge the other window again."
        } else {
            status = "Window fitted beside Today."
        }
    }

    deinit { timer?.invalidate() }
}

struct WindowControlSetupView: View {
    @ObservedObject var space: WindowSpaceController
    @Environment(\.dismiss) private var dismiss
    @State private var requested = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make room for Today").font(.title2.bold())
                    Text("Keep your dashboard beside your work.").foregroundStyle(.secondary)
                }
            }
            Text("Allow Today to move and resize other app windows when you enlarge them. This optional feature uses macOS Accessibility access.")
            if space.trusted {
                Label("Window control is ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
                Text("Today will fit enlarged windows beside your dashboard while Always on top is enabled.")
            } else {
                Text("1. In the macOS prompt, choose Open System Settings.\n2. Turn on the switch next to Today.")
                    .lineSpacing(6)
                Text("The permission page may be called Accessibility or Device Control and Data Access.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(requested ? "Open permission settings" : "Allow window control") {
                    if requested {
                        space.openPermissionSettings()
                    } else {
                        requested = true
                        space.requestAccess()
                    }
                }.buttonStyle(.borderedProminent)
                if requested {
                    Label("Waiting for you to enable Today…", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("Today is missing or its switch won’t work?") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Drag this Today icon into the Accessibility app list, then turn on its switch.")
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                                .resizable().frame(width: 48, height: 48)
                            Text("Today").font(.headline)
                            Image(systemName: "arrow.up.right")
                        }
                        .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                        .accessibilityLabel("Today app. Drag to Accessibility settings.")
                        Text("After an update, macOS may still list an older copy. Select that Today entry and press the minus button. Drag this icon into the list, then enable the new entry. An enabled switch alone doesn’t confirm access—wait for the green confirmation here.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
            }
            HStack {
                Spacer()
                Button(space.trusted ? "Done" : "Not now") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 440)
        .task {
            while !Task.isCancelled {
                space.refreshPermission()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
    }
}
