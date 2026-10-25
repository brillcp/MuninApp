import StoreKit
import SwiftUI

/// Account, subscription, security and about. A Settings window on Mac (⌘,), a tab on iOS.
struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptions

    /// Shows the Change Master Password sheet.
    @State private var isChangingPassword = false
    /// The recovery key to show in a sheet.
    @State private var recoveryKey: RecoveryKeyItem?
    /// Bumped by buttons for a light haptic.
    @State private var hapticTaps = 0
    /// Shows the paywall.
    @State private var isShowingPaywall = false
    /// iOS: shows the App Store's Manage Subscriptions sheet.
    @State private var isManagingSubscription = false
    /// True while Restore Purchases runs.
    @State private var isRestoring = false
    /// Shows the Delete Account confirmation.
    @State private var isConfirmingDeletion = false
    /// True while the account is being deleted.
    @State private var isDeletingAccount = false
    /// Why deleting the account failed, shown in an alert.
    @State private var deletionError: String?

    var body: some View {
        @Bindable var session = session
        Form {
            if auth.isSignedIn {
                Section {
                    AccountHeader(email: auth.email)
                        .listRowBackground(Color.clear)
                }

                if let status = subscriptions.status, status.required {
                    Section("settings.subscription") {
                        LabeledContent("settings.subscription.status") {
                            Text(LocalizedStringKey(status.active ? "settings.subscription.active" : "settings.subscription.inactive"))
                        }
                        if !status.active {
                            Button("subscription.subscribe", systemImage: "star") {
                                hapticTaps += 1
                                isShowingPaywall = true
                            }
                        }
                        Button("settings.subscription.restore", systemImage: "arrow.clockwise", action: restorePurchases)
                            .disabled(isRestoring)
                        #if os(iOS)
                        Button("settings.subscription.manage", systemImage: "creditcard") {
                            hapticTaps += 1
                            isManagingSubscription = true
                        }
                        #else
                        Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                            Label("settings.subscription.manage", systemImage: "creditcard")
                        }
                        #endif
                    }
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
                Link(destination: AppLinks.privacyPolicy) {
                    Label("settings.privacyPolicy", systemImage: "hand.raised")
                }
                Link(destination: AppLinks.termsOfUse) {
                    Label("settings.termsOfUse", systemImage: "doc.text")
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
                    Button("account.delete", systemImage: "person.crop.circle.badge.xmark", role: .destructive, action: confirmDeletion)
                        .foregroundStyle(.red)
                        .tint(.red)
                        .disabled(session.vault == nil || isDeletingAccount)
                } footer: {
                    if session.vault == nil {
                        Text("account.delete.locked")
                    }
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
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        .confirmationDialog("account.delete.title", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("account.delete", role: .destructive, action: deleteAccount)
        } message: {
            Text("account.delete.message")
        }
        .alert("account.delete.failed", item: $deletionError) { _ in
            Button("global.done") {}
        } message: { message in
            Text(message)
        }
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        #endif
        .buttonStyle(.plain)
        #if os(macOS)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }
}

private extension SettingsView {
    /// Syncs App Store purchases and links any active subscription to this account.
    func restorePurchases() {
        hapticTaps += 1
        Task {
            isRestoring = true
            defer { isRestoring = false }
            await subscriptions.restore(auth: auth)
        }
    }

    /// Asks before deleting the account.
    func confirmDeletion() {
        hapticTaps += 1
        isConfirmingDeletion = true
    }

    /// Deletes the account on Munin with the unlocked vault's proof, then signs out.
    func deleteAccount() {
        Task {
            isDeletingAccount = true
            defer { isDeletingAccount = false }
            do {
                try await auth.deleteAccount(proof: session.vault?.proof)
            } catch {
                deletionError = error.muninDescription
            }
        }
    }
}

/// The signed-in account: a centred accent circle with initials, and the email.
private struct AccountHeader: View {
    /// The signed-in email.
    let email: String?

    /// Sign in with Apple only gives Munin the email, so the initials come from
    /// its first part: "jane.doe@…" → "JD", "jane@…" → "J".
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

/// A recovery key, presented as a sheet item.
private struct RecoveryKeyItem: Identifiable {
    /// The recovery key, formatted for the user to write down.
    let key: String
    var id: String { key }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .environment(VaultSession())
        .environment(SubscriptionManager())
}
