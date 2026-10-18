import SwiftUI

/// Profile menu: who's signed in, the recovery key, and sign out.
struct AccountMenu: View {
    @Environment(AuthManager.self) private var auth
    @State private var recoveryKey: RecoveryKeySheetItem?

    var body: some View {
        Menu {
            if let email = auth.email {
                Text(email)
            }
            Button("Show Recovery Key", systemImage: "key") {
                recoveryKey = auth.userID
                    .flatMap { VaultKeyStore.load(userID: $0) }
                    .map { RecoveryKeySheetItem(key: VaultKeyStore.recoveryString(for: $0)) }
            }
            Divider()
            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                auth.signOut()
            }
        } label: {
            Label(auth.email ?? "Account", systemImage: "person.crop.circle")
        }
        .sheet(item: $recoveryKey) { item in
            RecoveryKeyView(recoveryKey: item.key)
        }
    }
}

private struct RecoveryKeySheetItem: Identifiable {
    let key: String
    var id: String { key }
}
