import SwiftUI
import Playgrounds

/// The app's root view: the lock screen, or the signed-in content.
///
/// One lock screen covers everything from sign-in through unlock, so its card
/// can animate between the steps. The view also starts the session for the
/// signed-in user, applies auto-lock, and drops the decrypted password list on
/// lock and sign-out. That list outlives the main view (the Mac menu bar uses
/// it too), so it has to be cleared explicitly.
///
/// Locking and unlocking animate the swap. iOS cross-fades with a slight zoom
/// (blurring the whole window during the swap stuttered there); the Mac uses a
/// blur replace (the zoom crashed there). It's a ZStack rather than a Group: a Group passes its
/// `.animation` to each child separately, so an inserted or removed child
/// never sees the value change and the transition doesn't run.
struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(VaultViewModel.self) private var vaultModel
    @Environment(SubscriptionManager.self) private var subscriptions
    /// A 2FA setup link (`otpauth://`) that opened Munin, waiting for the
    /// vault to unlock. Munin can be chosen under "Set Up Codes In".
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
            #if os(iOS)
            .transition(.opacity.combined(with: .scale(1.1)))
            #else
            .transition(.opacity.combined(with: .scale(1.1)))
            #endif
        }
        .animation(DesignKit.Motion.slowSmooth, value: showsLockScreen)
        .task(id: auth.userID, prepare)
        .onOpenURL(perform: openURL)
        .autoLock(session)
        .onChange(of: session.state) { _, state in
            if state != .unlocked { clearOnLock() }
        }
    }
}

private extension ContentView {
    /// Keeps a 2FA setup link until the vault is unlocked, where the 2FA
    /// screen asks to add it.
    func openURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "otpauth" || scheme == "otpauth-migration" else { return }
        pendingCodeLink = url
    }

    /// Works out the vault's state for the signed-in user.
    func prepare() async {
        await session.prepare(auth: auth)
    }

    /// Drops the decrypted passwords and the subscription state on lock or
    /// sign-out. The list's row animation is disabled for this, so the rows
    /// don't animate away during the lock transition.
    func clearOnLock() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            vaultModel.clear()
            subscriptions.stop()
        }
    }

    /// True while signed out, locked, checking the vault's state, or after
    /// failing to open it (the lock screen then shows an alert).
    var showsLockScreen: Bool {
        !auth.isSignedIn || session.state == .locked || session.state == .checking || session.failureMessage != nil
    }
}

/// What a signed-in user sees, depending on the vault's state.
///
/// The locked, checking and failed states render nothing here, because
/// `ContentView` shows its lock screen for them instead.
private struct SignedInContent: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session

    /// A 2FA setup link waiting to be added, passed on to the main view.
    @Binding var pendingCodeLink: URL?

    var body: some View {
        @Bindable var session = session
        switch session.state {
        case .unlocked:
            MainView(session: session, pendingCodeLink: $pendingCodeLink)
                .sheet(item: $session.newRecoveryKey) { item in
                    RecoveryKeyView(recoveryKey: item.key)
                }
        case .locked, .checking:
            EmptyView()
        case .needsMasterPassword:
            MasterPasswordSetupView()
        case .missingKey:
            MissingKeyView { recoveryString in
                session.restoreLegacyKey(recoveryString)
            } onRetry: {
                await session.prepare(auth: auth)
            }
        case .failed:
            EmptyView()
        }
    }
}
