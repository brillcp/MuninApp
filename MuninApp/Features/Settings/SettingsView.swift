import SwiftUI

/// Account, security and about. A Settings window on Mac (⌘,), a tab on iOS.
struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session

    @State private var isChangingPassword = false
    @State private var recoveryKey: RecoveryKeyItem?

    var body: some View {
        Form {
            if auth.isSignedIn {
                Section("settings.account") {
                    if let email = auth.email {
                        LabeledContent("settings.email") {
                            Text(verbatim: email)
                                .textSelection(.enabled)
                        }
                    }
                    Button("account.signOut", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        auth.signOut()
                    }
                }

                Section("settings.security") {
                    if let vault = session.vault {
                        Button("settings.changeMasterPassword", systemImage: "key.horizontal") {
                            isChangingPassword = true
                        }
                        Button("account.showRecoveryKey", systemImage: "key") {
                            recoveryKey = RecoveryKeyItem(key: VaultKeyStore.recoveryString(for: vault.key))
                        }
                        if session.canUseBiometrics {
                            Toggle("settings.biometrics", isOn: Binding(
                                get: { session.isBiometricUnlockEnabled },
                                set: { session.setBiometricUnlock($0) }
                            ))
                        }
                    } else {
                        Text("settings.locked")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("settings.about") {
                LabeledContent("settings.version") {
                    Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isChangingPassword) {
            ChangeMasterPasswordView()
        }
        .sheet(item: $recoveryKey) { item in
            RecoveryKeyView(recoveryKey: item.key)
        }
        #if os(macOS)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }
}

private struct RecoveryKeyItem: Identifiable {
    let key: String
    var id: String { key }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .environment(VaultSession())
}
