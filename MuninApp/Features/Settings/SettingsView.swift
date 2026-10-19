import SwiftUI

/// Account, security and about. A Settings window on Mac (⌘,), a tab on iOS.
struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session

    @State private var isChangingPassword = false
    @State private var recoveryKey: RecoveryKeyItem?
    @State private var hapticTaps = 0

    var body: some View {
        @Bindable var session = session
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
                        hapticTaps += 1
                        auth.signOut()
                    }
                    .tint(.red)
                }

                Section("settings.security") {
                    if let vault = session.vault {
                        Button("settings.changeMasterPassword", systemImage: "key.horizontal") {
                            hapticTaps += 1
                            isChangingPassword = true
                        }
                        Button("account.showRecoveryKey", systemImage: "key") {
                            hapticTaps += 1
                            recoveryKey = RecoveryKeyItem(key: VaultKeyStore.recoveryString(for: vault.key))
                        }
                        if session.canUseBiometrics {
                            Toggle("settings.biometrics", isOn: $session.isBiometricUnlockEnabled)
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
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
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
