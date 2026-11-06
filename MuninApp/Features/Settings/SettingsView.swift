import StoreKit
import SwiftUI
import UniformTypeIdentifiers

/// A view that shows account, subscription, security, data, and app information.
///
/// On macOS, this is the content of the Settings window. On iOS, it's a tab.
struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(AutoFillSetup.self) private var autoFill
    @Environment(\.openURL) private var openURL

    /// A Boolean value that indicates whether the Change Master Password sheet is presented.
    @State private var isChangingPassword = false
    /// The recovery key presented in a sheet.
    @State private var recoveryKey: RecoveryKeyItem?
    /// A counter that triggers a light haptic when incremented.
    @State private var hapticTaps = 0
    @State private var isShowingPaywall = false
    /// A Boolean value that indicates whether the system's Manage Subscriptions sheet is presented on iOS.
    @State private var isManagingSubscription = false
    @State private var isShowingAutoFillGuide = false
    @State private var isRestoring = false
    @State private var isConfirmingDeletion = false
    @State private var isDeletingAccount = false
    /// A description of why deleting the account failed, shown in an alert.
    @State private var deletionError: String?
    /// The export awaiting confirmation.
    @State private var pendingExport: ExportKind?
    /// A Boolean value that indicates whether an export is being loaded and decrypted.
    @State private var isPreparingExport = false
    /// The decrypted export, held in memory only until the save panel closes.
    @State private var exportDocument: ExportDocument?
    /// A Boolean value that indicates whether the save panel for ``exportDocument`` is presented.
    @State private var isSavingExport = false
    /// A description of why an export failed, shown in an alert.
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
                            Text(status.active ? "settings.subscription.active" : "settings.subscription.inactive")
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
                            Toggle(
                                session.usesFaceID ? "settings.biometrics.face" : "settings.biometrics.touch",
                                systemImage: session.usesFaceID ? DesignKit.Icon.faceID : DesignKit.Icon.touchID,
                                isOn: $session.isBiometricUnlockEnabled
                            )
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
                    Button(action: showAutoFillGuide) {
                        LabeledContent {
                            Text(LocalizedStringKey(autoFill.isEnabled == true ? "settings.autoFill.on" : "settings.autoFill.off"))
                        } label: {
                            Label("settings.autoFill", systemImage: DesignKit.Icon.autoFill)
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
                    Text(session.vault == nil ? "settings.export.locked" : "settings.export.footer")
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
        .focusEffectDisabled()
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
        .sheet(isPresented: $isShowingAutoFillGuide) {
            AutoFillSetupView()
        }
        .task(autoFill.refresh)
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

    func confirmPasswordExport() {
        hapticTaps += 1
        pendingExport = .passwords
    }

    func confirmTwoFactorExport() {
        hapticTaps += 1
        pendingExport = .twoFactor
    }

    /// Loads and decrypts the export, then presents the save panel.
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

    /// Reports an error if saving the export failed.
    func exportSaved(_ result: Result<URL, any Error>) {
        if case .failure(let error) = result {
            exportError = error.localizedDescription
        }
    }

    /// Releases the decrypted export when the save panel closes, whether it was saved or cancelled.
    func savePanelChanged() {
        if !isSavingExport { exportDocument = nil }
    }

    func showAutoFillGuide() {
        hapticTaps += 1
        isShowingAutoFillGuide = true
    }

    /// Opens subscription management.
    ///
    /// On iOS, this presents the system sheet. On macOS, it opens the App Store page.
    func manageSubscription() {
        #if os(iOS)
        isManagingSubscription = true
        #else
        openURL(AppLinks.manageSubscriptions)
        #endif
    }

    func confirmDeletion() {
        hapticTaps += 1
        isConfirmingDeletion = true
    }

    /// Deletes the account on the server, then signs out.
    ///
    /// The user confirms with Sign in with Apple, and the request includes the
    /// unlocked vault's proof. Dismissing the Apple sheet cancels the deletion.
    func deleteAccount() {
        Task {
            isDeletingAccount = true
            defer { isDeletingAccount = false }
            do {
                _ = try await auth.deleteAccount(proof: session.vault?.proof)
            } catch {
                deletionError = error.muninDescription
            }
        }
    }
}

/// The kinds of data that settings can export.
private enum ExportKind: Identifiable {
    /// Passwords, as a CSV file.
    case passwords
    /// Two-factor accounts, as `otpauth` links.
    case twoFactor

    var id: Self { self }
}

/// A recovery key, wrapped for presentation as a sheet item.
private struct RecoveryKeyItem: Identifiable {
    /// The recovery key, formatted for the user to write down.
    let key: String
    var id: String { key }
}
