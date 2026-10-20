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
                Section {
                    AccountHeader(email: auth.email)
                        .listRowBackground(Color.clear)
                }

                Section("settings.security") {
                    if let vault = session.vault {
                        Button("settings.changeMasterPassword", systemImage: "lock.shield") {
                            hapticTaps += 1
                            isChangingPassword = true
                        }
                        Button("account.showRecoveryKey", systemImage: "key") {
                            hapticTaps += 1
                            recoveryKey = RecoveryKeyItem(key: VaultKeyStore.recoveryString(for: vault.key))
                        }
                        if session.canUseBiometrics {
                            #if os(macOS)
                            Toggle("settings.biometrics.touch", systemImage: "faceid", isOn: $session.isBiometricUnlockEnabled)
                            #else
                            Toggle("settings.biometrics.face", systemImage: "faceid", isOn: $session.isBiometricUnlockEnabled)
                            #endif
                        }
                    } else {
                        Text("settings.locked")
                            .foregroundStyle(.secondary)
                    }
                    Picker("settings.autoLock", systemImage: "lock.fill", selection: $session.autoLockTimeout) {
                        ForEach(AutoLockTimeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout)
                        }
                    }
                }
            }

            Section("settings.about") {
                LabeledContent("settings.version") {
                    Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }

            if auth.isSignedIn {
                Section {
                    Button("account.signOut", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        hapticTaps += 1
                        auth.signOut()
                    }
                    .foregroundStyle(.red)
                    .tint(.red)
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
        .buttonStyle(.plain)
        #if os(macOS)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }
}

/// The signed-in account: a centred accent circle with initials, and the email.
private struct AccountHeader: View {
    let email: String?

    /// Sign in with Apple only gives Munin the email, so the initials come from
    /// its first part: "viktor.gidlof@…" → "VG", "viktor@…" → "V".
    private var initials: String {
        guard let local = email?.split(separator: "@").first else { return "?" }
        let parts = local.split(whereSeparator: { ".-_+".contains($0) })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        VStack(spacing: DesignKit.Spacing.Primitive.s12) {
            Text(verbatim: initials)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(.accent, in: .circle)
            if let email {
                Text(verbatim: email)
                    .font(.headline)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
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
