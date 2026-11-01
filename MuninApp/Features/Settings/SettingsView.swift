import StoreKit
import SwiftUI
import UniformTypeIdentifiers

/// Account, subscription, security and about. A Settings window on Mac (⌘,), a tab on iOS.
struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.openURL) private var openURL

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
    /// The export waiting for confirmation.
    @State private var pendingExport: ExportKind?
    /// True while an export is loaded and decrypted.
    @State private var isPreparingExport = false
    /// The decrypted export, held only until the save panel closes.
    @State private var exportDocument: ExportDocument?
    /// Shows the save panel for `exportDocument`.
    @State private var isSavingExport = false
    /// Why an export failed, shown in an alert.
    @State private var exportError: String?

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
                            Button("subscription.subscribe", systemImage: DesignKit.Icon.subscribe) {
                                hapticTaps += 1
                                isShowingPaywall = true
                            }
                        }
                        Button("settings.subscription.restore", systemImage: DesignKit.Icon.restorePurchases, action: restorePurchases)
                            .disabled(isRestoring)
                        #if os(iOS)
                        Button("settings.subscription.manage", systemImage: DesignKit.Icon.manageSubscription) {
                            hapticTaps += 1
                            isManagingSubscription = true
                        }
                        #else
                        Link(destination: AppLinks.manageSubscriptions) {
                            Label("settings.subscription.manage", systemImage: DesignKit.Icon.manageSubscription)
                        }
                        #endif
                    }
                }

                Section("settings.security") {
                    if let vault = session.vault {
                        Button("settings.changeMasterPassword", systemImage: DesignKit.Icon.masterPassword) {
                            hapticTaps += 1
                            isChangingPassword = true
                        }
                        Button("account.showRecoveryKey", systemImage: DesignKit.Icon.recoveryKey) {
                            hapticTaps += 1
                            recoveryKey = RecoveryKeyItem(key: VaultKeyStore.recoveryString(for: vault.key))
                        }
                        if session.canUseBiometrics {
                            Toggle(session.usesFaceID ? "settings.biometrics.face" : "settings.biometrics.touch", systemImage: session.usesFaceID ? DesignKit.Icon.faceID : DesignKit.Icon.touchID, isOn: $session.isBiometricUnlockEnabled)
                        }
                    } else {
                        Text("settings.locked")
                            .foregroundStyle(.secondary)
                    }
                    Picker("settings.autoLock", systemImage: DesignKit.Icon.locked, selection: $session.autoLockTimeout) {
                        ForEach(AutoLockTimeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout)
                        }
                    }
                }
            }

            if auth.isSignedIn {
                Section {
                    Button("settings.export.passwords", systemImage: DesignKit.Icon.export, action: confirmPasswordExport)
                    Button("settings.export.twoFactor", systemImage: DesignKit.Icon.export, action: confirmTwoFactorExport)
                } header: {
                    Text("settings.data")
                } footer: {
                    Text(LocalizedStringKey(session.vault == nil ? "settings.export.locked" : "settings.export.footer"))
                }
                .disabled(session.vault == nil || isPreparingExport)
            }

            Section("settings.about") {
                LabeledContent("settings.version") {
                    Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
                Link(destination: AppLinks.privacyPolicy) {
                    Label("settings.privacyPolicy", systemImage: DesignKit.Icon.privacyPolicy)
                }
                Link(destination: AppLinks.termsOfUse) {
                    Label("settings.termsOfUse", systemImage: DesignKit.Icon.termsOfUse)
                }
            }

            if auth.isSignedIn {
                Section {
                    Button("account.signOut", systemImage: DesignKit.Icon.signOut, role: .destructive) {
                        hapticTaps += 1
                        auth.signOut()
                    }
                    .foregroundStyle(.red)
                    .tint(.red)
                    Button("account.delete", systemImage: DesignKit.Icon.deleteAccount, role: .destructive, action: confirmDeletion)
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
            if subscriptions.status?.active == true {
                Button("settings.subscription.manage", action: manageSubscription)
            }
        } message: {
            Text("account.delete.message")
        }
        .alert("account.delete.failed", item: $deletionError) { _ in
            Button("global.done") {}
        } message: { message in
            Text(message)
        }
        .confirmationDialog("settings.export.title", item: $pendingExport, titleVisibility: .visible) { kind in
            Button("settings.export.confirm") { export(kind) }
        } message: { _ in
            Text("settings.export.message")
        }
        .fileExporter(
            isPresented: $isSavingExport,
            document: exportDocument,
            contentType: exportDocument?.contentType ?? .plainText,
            defaultFilename: exportDocument?.filename,
            onCompletion: exportSaved
        )
        .onChange(of: isSavingExport, savePanelChanged)
        .alert("settings.export.failed", item: $exportError) { _ in
            Button("global.done") {}
        } message: { message in
            Text(message)
        }
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        #endif
        .buttonStyle(.plain)
        #if os(macOS)
        .frame(width: 460, height: 620)
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

    /// Asks before exporting the passwords.
    func confirmPasswordExport() {
        hapticTaps += 1
        pendingExport = .passwords
    }

    /// Asks before exporting the 2FA accounts.
    func confirmTwoFactorExport() {
        hapticTaps += 1
        pendingExport = .twoFactor
    }

    /// Loads and decrypts the export, then opens the save panel.
    func export(_ kind: ExportKind) {
        guard let vault = session.vault else { return }
        Task {
            isPreparingExport = true
            defer { isPreparingExport = false }
            do {
                switch kind {
                case .passwords:
                    let data = try await VaultExporter.passwordsCSV(vault: vault, auth: auth)
                    exportDocument = ExportDocument(data: data, contentType: .commaSeparatedText, filename: Localized("settings.export.passwords.filename"))
                case .twoFactor:
                    let data = try await VaultExporter.twoFactorLinks(vault: vault, auth: auth)
                    exportDocument = ExportDocument(data: data, contentType: .plainText, filename: Localized("settings.export.twoFactor.filename"))
                }
                isSavingExport = true
            } catch {
                exportError = error.muninDescription
            }
        }
    }

    /// Shows why saving failed.
    func exportSaved(_ result: Result<URL, any Error>) {
        if case .failure(let error) = result {
            exportError = error.localizedDescription
        }
    }

    /// Drops the decrypted export from memory when the save panel closes,
    /// whether it was saved or cancelled.
    func savePanelChanged() {
        if !isSavingExport { exportDocument = nil }
    }

    /// Opens subscription management: the system sheet on iOS, the App Store page on Mac.
    func manageSubscription() {
        #if os(iOS)
        isManagingSubscription = true
        #else
        openURL(AppLinks.manageSubscriptions)
        #endif
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

/// What Settings can export.
private enum ExportKind: Identifiable {
    /// The passwords, as CSV.
    case passwords
    /// The 2FA accounts, as `otpauth` links.
    case twoFactor

    var id: Self { self }
}

/// A recovery key, presented as a sheet item.
private struct RecoveryKeyItem: Identifiable {
    /// The recovery key, formatted for the user to write down.
    let key: String
    var id: String { key }
}
