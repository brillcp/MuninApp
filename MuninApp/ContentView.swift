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
/// On iOS, locking and unlocking cross-fade the two with a slight zoom
/// (blurring the whole window during the swap stuttered). The Mac swaps them
/// without animation: the transition crashed there. It's a ZStack rather than a Group: a Group passes its
/// `.animation` to each child separately, so an inserted or removed child
/// never sees the value change and the transition doesn't run.
struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(VaultViewModel.self) private var vaultModel

    var body: some View {
        ZStack {
            Group {
                if showsLockScreen {
                    LockView()
                } else {
                    SignedInContent()
                }
            }
            #if os(iOS)
            .transition(.opacity.combined(with: .scale(1.1)))
            #endif
        }
        #if os(iOS)
        .animation(.smooth(duration: 0.45), value: showsLockScreen)
        #endif
        .task(id: auth.userID) { await session.prepare(auth: auth) }
        .autoLock(session)
        .onChange(of: session.state) { _, state in
            if state != .unlocked { vaultModel.clear() }
        }
    }

    /// True while signed out, locked, or still checking the vault's state.
    private var showsLockScreen: Bool {
        !auth.isSignedIn || session.state == .locked || session.state == .checking
    }
}

/// What a signed-in user sees, depending on the vault's state.
///
/// The locked and checking states render nothing here, because `ContentView`
/// shows its lock screen for them instead.
private struct SignedInContent: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session

    var body: some View {
        @Bindable var session = session
        switch session.state {
        case .unlocked:
            MainView(session: session)
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
        case .failed(let message):
            ContentUnavailableView {
                Label("errors.openVault.title", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("global.tryAgain") { Task { await session.prepare(auth: auth) } }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(VaultSession())
        .environment(VaultViewModel(session: VaultSession()))
}
