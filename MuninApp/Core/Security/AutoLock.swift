import SwiftUI
#if os(macOS)
import AppKit
#endif

/// How long Munin stays unlocked after leaving it. Picked in Settings.
enum AutoLockTimeout: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case never = -1

    var id: Int { rawValue }

    /// The option's name in the Settings picker.
    var title: LocalizedStringKey {
        switch self {
        case .immediately: "autoLock.immediately"
        case .oneMinute: "autoLock.oneMinute"
        case .fiveMinutes: "autoLock.fiveMinutes"
        case .fifteenMinutes: "autoLock.fifteenMinutes"
        case .never: "autoLock.never"
        }
    }

    /// The timeout in seconds, or nil for `.never`.
    var seconds: TimeInterval? { self == .never ? nil : TimeInterval(rawValue) }
}

extension View {
    /// Locks the vault automatically, following the session's auto-lock setting.
    ///
    /// Only while Munin isn't the app in use: being idle in Munin never locks it.
    ///
    /// - iOS: on leaving the app ("Immediately"), or on coming back after the
    ///   timeout. The phone's own screen lock sends the app to the background,
    ///   so inactivity is covered by that.
    /// - macOS: when the Mac sleeps or its screen locks, on switching to another
    ///   app ("Immediately"), or once the timeout has passed since switching
    ///   to another app.
    ///
    /// "Never" turns all of it off.
    func autoLock(_ session: VaultSession) -> some View {
        modifier(AutoLockModifier(session: session))
    }
}

/// The implementation behind `View.autoLock(_:)`.
private struct AutoLockModifier: ViewModifier {
    /// The session to lock.
    let session: VaultSession

    @Environment(\.scenePhase) private var scenePhase
    /// When Munin went to the background (iOS) or stopped being the active
    /// app (Mac), to measure the time away.
    @State private var backgroundedAt: Date?

    /// The chosen timeout in seconds, or nil for "Never".
    private var timeout: TimeInterval? { session.autoLockTimeout.seconds }
    /// Whether the vault is currently unlocked.
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
                backgroundedAt = .now
                if timeout == 0 { session.lock() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                backgroundedAt = nil
            }
            .task(id: BackgroundCheck(isUnlocked: isUnlocked, timeout: timeout, backgroundedAt: backgroundedAt)) {
                guard isUnlocked, let timeout, timeout > 0, let backgroundedAt else { return }
                let remaining = timeout - Date.now.timeIntervalSince(backgroundedAt)
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                guard !Task.isCancelled else { return }
                session.lock()
            }
            #endif
    }

    #if os(macOS)
    /// The inputs of the Mac background timer. The timer restarts whenever one
    /// changes, and stops when Munin becomes the active app again.
    private struct BackgroundCheck: Equatable {
        let isUnlocked: Bool
        let timeout: TimeInterval?
        let backgroundedAt: Date?
    }

    /// Locks on sleep or screen lock, unless auto-lock is set to "Never".
    private func lockUnlessNever() {
        if timeout != nil { session.lock() }
    }
    #endif
}
