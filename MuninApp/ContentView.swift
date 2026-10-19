import SwiftUI
import Playgrounds

struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(VaultViewModel.self) private var vaultModel

    var body: some View {
        Group {
            if showsLockScreen {
                // One lock screen from sign-in through unlock, so its card can
                // animate between the steps.
                LockView()
            } else {
                SignedInContent()
            }
        }
        .task(id: auth.userID) { await session.prepare(auth: auth) }
        // The password list outlives the main view (the menu bar uses it), so
        // drop it explicitly on lock and sign out.
        .onChange(of: session.state) { _, state in
            if state != .unlocked { vaultModel.clear() }
        }
    }

    private var showsLockScreen: Bool {
        !auth.isSignedIn || session.state == .locked || session.state == .checking
    }
}

/// What a signed-in user sees, depending on the vault's state.
private struct SignedInContent: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session

    var body: some View {
        switch session.state {
        case .unlocked:
            MainView(session: session)
                .sheet(isPresented: isShowingNewRecoveryKey) {
                    if let key = session.newRecoveryKey {
                        RecoveryKeyView(recoveryKey: key)
                    }
                }
        case .locked, .checking:
            // Shown by ContentView's lock screen instead.
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

    /// A brand-new vault shows its recovery key once.
    private var isShowingNewRecoveryKey: Binding<Bool> {
        Binding(
            get: { session.newRecoveryKey != nil },
            set: { if !$0 { session.newRecoveryKey = nil } }
        )
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(VaultSession())
        .environment(VaultViewModel(session: VaultSession()))
}
