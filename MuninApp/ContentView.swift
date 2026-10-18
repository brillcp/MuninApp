import SwiftUI
import Playgrounds

struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @State private var appLock = AppLock()
    @State private var keyManager = VaultKeyManager()

    var body: some View {
        Group {
            if auth.isSignedIn {
                SignedInContent(keyManager: keyManager)
                    .overlay {
                        if !appLock.isUnlocked { LockView() }
                    }
                    .task { await appLock.unlock() }
                    .task(id: auth.userID) { await keyManager.prepare(auth: auth) }
            } else {
                SignInView()
            }
        }
        .environment(appLock)
    }

}

/// What a signed-in user sees, depending on whether the vault key is ready.
private struct SignedInContent: View {
    let keyManager: VaultKeyManager
    @Environment(AuthManager.self) private var auth

    var body: some View {
        switch keyManager.state {
        case .ready:
            MainView()
        case .checking:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .missing:
            MissingKeyView { recoveryString in
                keyManager.restore(recoveryString, auth: auth)
            } onRetry: {
                await keyManager.prepare(auth: auth)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("errors.openVault.title", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("global.tryAgain") { Task { await keyManager.prepare(auth: auth) } }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
