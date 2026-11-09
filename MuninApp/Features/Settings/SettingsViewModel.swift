import Foundation
import Observation
import UniformTypeIdentifiers

/// The model behind Settings: restoring purchases, exporting the vault, and
/// deleting the account.
///
/// The Settings window on macOS and the Settings tab on iOS share one instance.
@Observable
final class SettingsViewModel {
    private let api: any MuninAPI
    private let auth: AuthManager
    private let session: VaultSession
    private let subscriptions: SubscriptionManager

    /// A Boolean value that indicates whether purchases are being restored.
    private(set) var isRestoring = false
    /// A Boolean value that indicates whether the account is being deleted.
    private(set) var isDeletingAccount = false
    /// A Boolean value that indicates whether an export is being loaded and decrypted.
    private(set) var isPreparingExport = false
    /// The decrypted export, held in memory only until the save panel closes.
    private(set) var exportDocument: ExportDocument?

    /// The export awaiting confirmation.
    var pendingExport: ExportKind?
    /// A Boolean value that indicates whether the save panel for ``exportDocument`` is presented.
    ///
    /// The decrypted export is released when the panel closes, whether it was saved or cancelled.
    var isSavingExport = false {
        didSet { if !isSavingExport { exportDocument = nil } }
    }
    /// A description of why an export failed, shown in an alert.
    var exportError: String?
    /// A description of why deleting the account failed, shown in an alert.
    var deletionError: String?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - api: The API that loads the data to export.
    ///   - auth: The authentication manager that deletes the account.
    ///   - session: The session that provides the vault key and proof.
    ///   - subscriptions: The subscription manager that restores purchases.
    init(api: any MuninAPI, auth: AuthManager, session: VaultSession, subscriptions: SubscriptionManager) {
        self.api = api
        self.auth = auth
        self.session = session
        self.subscriptions = subscriptions
    }
}

// MARK: - Public functions
extension SettingsViewModel {
    /// The kinds of data that settings can export.
    enum ExportKind: Identifiable {
        /// Passwords, as a CSV file.
        case passwords
        /// Two-factor accounts, as `otpauth` links.
        case twoFactor

        var id: Self { self }
    }

    /// Syncs App Store purchases and links any active subscription to this account.
    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        await subscriptions.restore()
    }

    /// Loads the data, decrypts it off the main actor, and presents the save panel.
    func export(_ kind: ExportKind) async {
        guard let vault = session.vault, !isPreparingExport else { return }
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            switch kind {
            case .passwords:
                let records = try await api.passwords()
                let data = try await Task.detached(priority: .userInitiated) {
                    try VaultExporter.passwordsCSV(from: records, vault: vault)
                }.value
                exportDocument = ExportDocument(data: data, contentType: .commaSeparatedText, filename: Localized("settings.export.passwords.filename"))
            case .twoFactor:
                let records = try await api.entries()
                let data = try await Task.detached(priority: .userInitiated) {
                    try VaultExporter.twoFactorLinks(from: records, vault: vault)
                }.value
                exportDocument = ExportDocument(data: data, contentType: .plainText, filename: Localized("settings.export.twoFactor.filename"))
            }
            isSavingExport = true
        } catch {
            exportError = error.muninDescription
        }
    }

    /// Reports an error if saving the export failed.
    func exportSaved(_ result: Result<URL, any Error>) {
        if case .failure(let error) = result {
            exportError = error.localizedDescription
        }
    }

    /// Deletes the account on the server, then signs out.
    ///
    /// The user confirms with Sign in with Apple, and the request includes the
    /// unlocked vault's proof. Dismissing the Apple sheet cancels the deletion.
    func deleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            _ = try await auth.deleteAccount(proof: session.vault?.proof)
        } catch {
            deletionError = error.muninDescription
        }
    }
}
