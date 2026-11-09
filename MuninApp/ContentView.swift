import Playgrounds
import SwiftUI

/// The app's root view, which shows either the lock screen or the signed-in content.
///
/// A single lock screen covers every step from sign-in through unlock, so its
/// card can animate between steps. This view also prepares the session for the
/// signed-in user, applies auto-lock, and clears decrypted data on lock and
/// sign-out. The password list outlives the main view, because the macOS menu
/// bar uses it too, so it must be cleared explicitly.
///
/// The swap between the lock screen and the content is wrapped in a `ZStack`
/// rather than a `Group`. A `Group` applies its animation to each child
/// separately, so an inserted or removed child never observes the value change
/// and its transition doesn't run.
struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(VaultViewModel.self) private var vaultModel
    @Environment(TwoFactorViewModel.self) private var twoFactorModel
    @Environment(SubscriptionManager.self) private var subscriptions
    /// The app's AutoFill status, refreshed whenever the app becomes active.
    @Environment(AutoFillSetup.self) private var autoFill
    @Environment(\.scenePhase) private var scenePhase
    /// A two-factor setup link that opened the app, held until the vault unlocks.
    ///
    /// The app handles `otpauth` and `otpauth-migration` links, for example
    /// when chosen under "Set Up Codes In" in the system settings.
    @State private var pendingCodeLink: URL?

    var body: some View {
        ZStack {
            Group {
                if showsLockScreen {
                    LockView()
                } else {
                    SignedInContent(pendingCodeLink: $pendingCodeLink)
                }
            }
            .transition(.opacity.combined(with: .scale(1.1)))
        }
        .animation(DesignKit.Motion.slowSmooth, value: showsLockScreen)
        .task(id: auth.userID, prepare)
        .onOpenURL(perform: openURL)
        .onChange(of: scenePhase, initial: true, becameActive)
        .autoLock(session)
        .onChange(of: session.state) { _, state in
            if state != .unlocked { clearOnLock() }
        }
    }
}

private extension ContentView {
    /// Holds a two-factor setup link until the vault unlocks, when the two-factor screen offers to add it.
    func openURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "otpauth" || scheme == "otpauth-migration" else { return }
        pendingCodeLink = url
    }

    /// Refreshes the AutoFill status and the Face ID or Touch ID capability,
    /// which can change in the system settings while the app is in the background.
    func becameActive() {
        guard scenePhase == .active else { return }
        session.refreshBiometry()
        Task { await autoFill.refresh() }
    }

    /// Determines the vault's state for the signed-in user.
    func prepare() async {
        await session.prepare()
    }

    /// Clears the decrypted passwords, 2FA accounts, and subscription state on lock or sign-out.
    ///
    /// Animations are disabled so the list's rows don't animate away during the lock transition.
    func clearOnLock() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            vaultModel.clear()
            twoFactorModel.clear()
            subscriptions.stop()
        }
    }

    /// A Boolean value that indicates whether the lock screen is shown.
    ///
    /// This is `true` while signed out, locked, checking the vault's state, or
    /// after the vault fails to open, in which case the lock screen shows an alert.
    var showsLockScreen: Bool {
        !auth.isSignedIn || session.state == .locked || session.state == .checking || session.failureMessage != nil
    }
}
