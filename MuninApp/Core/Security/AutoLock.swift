import SwiftUI
#if os(macOS)
import AppKit
import CoreGraphics
#endif

/// How long Munin stays unlocked without use. Picked in Settings.
enum AutoLockTimeout: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case never = -1

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .immediately: "autoLock.immediately"
        case .oneMinute: "autoLock.oneMinute"
        case .fiveMinutes: "autoLock.fiveMinutes"
        case .fifteenMinutes: "autoLock.fifteenMinutes"
        case .never: "autoLock.never"
        }
    }

    /// Nil for `.never`.
    var seconds: TimeInterval? { self == .never ? nil : TimeInterval(rawValue) }
}

extension View {
    /// Locks the vault on its own:
    /// - iOS: on leaving the app ("Immediately"), or on coming back after the
    ///   timeout. The phone's own screen lock sends the app to the background,
    ///   so inactivity is covered by that.
    /// - macOS: when the Mac sleeps or its screen locks, on switching to another
    ///   app ("Immediately"), and after the timeout without any keyboard or
    ///   mouse input.
    /// "Never" turns all of it off.
    func autoLock(_ session: VaultSession) -> some View {
        modifier(AutoLockModifier(session: session))
    }
}

private struct AutoLockModifier: ViewModifier {
    let session: VaultSession

    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundedAt: Date?

    private var timeout: TimeInterval? { session.autoLockTimeout.seconds }
    private var isUnlocked: Bool { session.state == .unlocked }

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    backgroundedAt = .now
                    if timeout == 0 { session.lock() }
                case .active:
                    if let backgroundedAt, let timeout, Date.now.timeIntervalSince(backgroundedAt) >= timeout {
                        session.lock()
                    }
                    backgroundedAt = nil
                default:
                    break
                }
            }
            #else
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                lockUnlessNever()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in
                lockUnlessNever()
            }
            .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))) { _ in
                lockUnlessNever()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                if timeout == 0 { session.lock() }
            }
            .task(id: IdleCheck(isUnlocked: isUnlocked, timeout: timeout)) {
                guard isUnlocked, let timeout, timeout > 0 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    if Self.secondsSinceLastInput >= timeout {
                        session.lock()
                        return
                    }
                }
            }
            #endif
    }

    #if os(macOS)
    private struct IdleCheck: Equatable {
        let isUnlocked: Bool
        let timeout: TimeInterval?
    }

    private func lockUnlessNever() {
        if timeout != nil { session.lock() }
    }

    /// System-wide time since the last keyboard, mouse or trackpad event.
    private static var secondsSinceLastInput: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
    #endif
}
