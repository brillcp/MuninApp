import Foundation
import Observation

/// An object that imports a CSV file into the vault and the 2FA list.
///
/// It reads the file, compares it with what's stored, and once the user
/// confirms, uploads the new passwords and then the new 2FA accounts.
@Observable
final class PasswordImporter {
    private let vaultModel: VaultViewModel
    private let twoFactorModel: TwoFactorViewModel

    /// A parsed file waiting for confirmation.
    var plan: VaultViewModel.ImportPlan?
    /// The result: how many items were added, or why the file couldn't be read.
    var message: String?

    /// Creates an importer that adds to the given models.
    init(vaultModel: VaultViewModel, twoFactorModel: TwoFactorViewModel) {
        self.vaultModel = vaultModel
        self.twoFactorModel = twoFactorModel
    }
}

// MARK: - Public functions
extension PasswordImporter {
    /// Reads a CSV file in memory and asks the user to confirm the import.
    ///
    /// The file's 2FA accounts are checked against the existing 2FA list,
    /// which loads first if needed.
    func prepare(from url: URL) async {
        let parsed: PasswordCSVParser.Import
        do {
            parsed = try Self.parse(url)
        } catch {
            message = error.localizedDescription
            return
        }
        if !parsed.twoFactorAccounts.isEmpty, !twoFactorModel.hasLoaded {
            await twoFactorModel.refresh()
        }
        let newAccounts = twoFactorModel.newAccounts(in: parsed.twoFactorAccounts)
        plan = vaultModel.planImport(parsed.passwords, twoFactorAccounts: newAccounts)
    }

    /// Imports the plan's passwords, then its 2FA accounts, and reports how
    /// many of each were added.
    func run(_ plan: VaultViewModel.ImportPlan) async {
        let saved = await vaultModel.runImport(plan)
        guard !plan.twoFactorAccounts.isEmpty else {
            message = Localized("import.done.message", saved)
            return
        }
        do {
            let added = try await twoFactorModel.add(plan.twoFactorAccounts)
            message = Localized("import.done.messageWithCodes", saved, added)
        } catch {
            message = Localized("import.done.message", saved) + "\n\n" + error.muninDescription
        }
    }
}

// MARK: - Private functions
private extension PasswordImporter {
    /// Reads and parses a file the user picked or dropped.
    static func parse(_ url: URL) throws -> PasswordCSVParser.Import {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        return try PasswordCSVParser.parse(try Data(contentsOf: url))
    }
}
