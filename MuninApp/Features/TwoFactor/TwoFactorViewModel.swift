import Foundation
import Observation

/// An observable model that loads, decrypts, and manages the user's two-factor accounts.
///
/// Entries are fetched from the server and decrypted with the unlocked vault
/// key. Views compute codes from the decrypted accounts. The 2FA tab, Search,
/// and imports share a single instance.
@Observable
final class TwoFactorViewModel {
    /// The session that provides the vault key.
    ///
    /// Read on each use, so a lock or a changed master password takes effect immediately.
    private let session: VaultSession
    private let api: any MuninAPI
    private let user: any UserSession

    /// The decrypted accounts.
    private(set) var items: [VaultItem] = []
    /// A description of the last load or delete error.
    private(set) var errorMessage: String?
    /// A Boolean value that indicates whether a load is in progress.
    private(set) var isLoading = false
    /// A Boolean value that indicates whether the first load has finished, successfully or not.
    private(set) var hasLoaded = false
    /// The number of entries that couldn't be decrypted with the vault key.
    private(set) var undecryptableCount = 0

    /// Creates a view model.
    ///
    /// - Parameters:
    ///   - session: The session that provides the vault key.
    ///   - api: The API that stores the encrypted accounts.
    ///   - user: The signed-in user.
    init(session: VaultSession, api: any MuninAPI, user: any UserSession) {
        self.session = session
        self.api = api
        self.user = user
    }
}

// MARK: - Public functions
extension TwoFactorViewModel {
    /// Loads entries from the server and decrypts them off the main actor.
    ///
    /// Signs the user out if the server rejects their token.
    func refresh() async {
        guard user.isSignedIn else {
            clear()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let entries = try await api.entries()
            let vault = try unlockedVault()
            let decoded = await VaultDecoder.twoFactorItems(from: entries, vault: vault)
            // The vault may have locked while the entries were decrypting.
            guard session.vault?.userID == vault.userID else { return }
            items = decoded.items
            undecryptableCount = decoded.failures
            errorMessage = nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch where Task.isCancelled {
            // URLSession reports a cancelled task as a network error.
            return
        } catch let error where error.isMuninAuthRejection {
            user.signOut()
            clear()
        } catch {
            errorMessage = error.muninDescription
            hasLoaded = true
        }
    }

    /// Encrypts and uploads accounts, skipping exact duplicates.
    ///
    /// Accounts saved before a failure still join the list.
    ///
    /// - Returns: The number of accounts added.
    /// - Throws: An error if the vault is locked, or if encryption or an upload fails.
    @discardableResult
    func add(_ accounts: [OTPAccount]) async throws -> Int {
        let vault = try unlockedVault()
        var added: [VaultItem] = []
        defer { items.append(contentsOf: added) }
        for account in newAccounts(in: accounts) {
            let ciphertext = try VaultDecoder.seal(account, vault: vault)
            let entry = try await api.createEntry(ciphertext: ciphertext)
            added.append(VaultItem(id: entry.id, account: account))
        }
        return added.count
    }

    /// Returns the accounts that aren't stored yet, with repeats removed.
    func newAccounts(in accounts: [OTPAccount]) -> [OTPAccount] {
        var seen = Set(items.map(\.account))
        return accounts.filter { seen.insert($0).inserted }
    }

    /// Deletes an entry on the server, using the master password proof, and removes it from the list.
    func delete(_ item: VaultItem) async {
        do {
            let vault = try unlockedVault()
            try await api.deleteEntry(id: item.id, proof: vault.proof)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.muninDescription
        }
    }

    /// Removes all decrypted accounts, for example when the vault locks or the user signs out.
    func clear() {
        items = []
        errorMessage = nil
        undecryptableCount = 0
        hasLoaded = false
    }
}

// MARK: - Private functions
private extension TwoFactorViewModel {
    /// Returns the unlocked vault.
    ///
    /// - Throws: ``VaultError/keyMissing`` while the vault is locked.
    func unlockedVault() throws -> UnlockedVault {
        guard let vault = session.vault else { throw VaultError.keyMissing }
        return vault
    }
}
