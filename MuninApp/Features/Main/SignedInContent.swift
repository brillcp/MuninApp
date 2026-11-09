import SwiftUI

/// A view that shows the signed-in user's content for the vault's current state.
///
/// The locked, checking, and failed states render nothing, because
/// ``ContentView`` shows the lock screen for them instead.
struct SignedInContent: View {
    @Environment(VaultSession.self) private var session

    /// A pending two-factor setup link, passed to the main view.
    @Binding var pendingCodeLink: URL?

    var body: some View {
        @Bindable var session = session
        switch session.state {
        case .unlocked:
            MainView(pendingCodeLink: $pendingCodeLink)
                .sheet(item: $session.newRecoveryKey) { item in
                    RecoveryKeyView(recoveryKey: item.key)
                }
        case .locked, .checking, .failed:
            EmptyView()
        case .needsMasterPassword:
            MasterPasswordSetupView()
        }
    }
}
