import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The time the vault stays unlocked after the user leaves the app.
enum AutoLockTimeout: Int, CaseIterable, Identifiable {
    /// Locks as soon as the user leaves the app.
    case immediately = 0
    /// Locks one minute after the user leaves the app.
    case oneMinute = 60
    /// Locks five minutes after the user leaves the app.
    case fiveMinutes = 300
    /// Locks fifteen minutes after the user leaves the app.
    case fifteenMinutes = 900
    /// Never locks automatically.
    case never = -1

    /// The stable identity of the timeout, its raw value.
    var id: Int { rawValue }

    /// The localized title shown in Settings.
    var title: LocalizedStringKey {
        switch self {
        case .immediately: "autoLock.immediately"
        case .oneMinute: "autoLock.oneMinute"
        case .fiveMinutes: "autoLock.fiveMinutes"
        case .fifteenMinutes: "autoLock.fifteenMinutes"
        case .never: "autoLock.never"
        }
    }

    /// The timeout in seconds, or `nil` for ``never``.
    var seconds: TimeInterval? { self == .never ? nil : TimeInterval(rawValue) }
}

extension View {
    /// Locks the vault automatically according to the session's auto-lock timeout.
    ///
    /// The vault locks only while the app isn't in use; inactivity inside the
    /// app never locks it.
    ///
    /// - On iOS, the vault locks when the app moves to the background if the
    ///   timeout is ``AutoLockTimeout/immediately``, or when the app returns
    ///   after the timeout has elapsed. The device's screen lock moves the app
    ///   to the background, so it also covers inactivity.
    /// - On macOS, the vault locks when the Mac sleeps or its screen locks,
    ///   when another app becomes active if the timeout is
    ///   ``AutoLockTimeout/immediately``, or once the timeout elapses after
    ///   another app becomes active.
    ///
    /// ``AutoLockTimeout/never`` turns automatic locking off.
    ///
    /// - Parameter session: The session to lock.
    func autoLock(_ session: VaultSession) -> some View {
        modifier(AutoLockModifier(session: session))
    }
}

/// The view modifier that implements ``SwiftUI/View/autoLock(_:)``.
private struct AutoLockModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    /// The date the app moved to the background on iOS, or stopped being the
    /// active app on macOS. Used to measure how long the user was away.
    @State private var backgroundedAt: Date?

    let session: VaultSession

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
}

private extension AutoLockModifier {
    /// The selected timeout in seconds, or `nil` if auto-lock is off.
    var timeout: TimeInterval? { session.autoLockTimeout.seconds }
    var isUnlocked: Bool { session.state == .unlocked }

    #if os(macOS)
    /// The inputs of the macOS background timer.
    ///
    /// The timer restarts whenever an input changes. Clearing `backgroundedAt`
    /// when the app becomes active again cancels it.
    struct BackgroundCheck: Equatable {
        let isUnlocked: Bool
        let timeout: TimeInterval?
        let backgroundedAt: Date?
    }

    /// Locks the vault on sleep or screen lock, unless auto-lock is off.
    func lockUnlessNever() {
        if timeout != nil { session.lock() }
    }
    #endif
}
