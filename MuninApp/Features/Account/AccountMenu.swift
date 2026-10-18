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
            Button("account.showRecoveryKey", systemImage: "key") {
                recoveryKey = auth.userID
                    .flatMap { VaultKeyStore.load(userID: $0) }
                    .map { RecoveryKeySheetItem(key: VaultKeyStore.recoveryString(for: $0)) }
            }
            Divider()
            Button("account.signOut", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                auth.signOut()
            }
        } label: {
            Label {
                if let email = auth.email {
                    Text(email)
                } else {
                    Text("account.menu.title")
                }
            } icon: {
                Image(systemName: "person.crop.circle")
            }
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
