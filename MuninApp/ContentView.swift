import SwiftUI
import Playgrounds

struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session

    var body: some View {
        Group {
            if auth.isSignedIn {
                SignedInContent()
            } else {
                SignInView()
            }
        }
        .task(id: auth.userID) { await session.prepare(auth: auth) }
    }
}

/// What a signed-in user sees, depending on the vault's state.
private struct SignedInContent: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session

    var body: some View {
        switch session.state {
        case .unlocked:
            if let vault = session.vault {
                MainView(vault: vault)
                    .sheet(isPresented: isShowingNewRecoveryKey) {
                        if let key = session.newRecoveryKey {
                            RecoveryKeyView(recoveryKey: key)
                        }
                    }
            }
        case .locked:
            LockView()
        case .needsMasterPassword:
            MasterPasswordSetupView()
        case .checking:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
