import CryptoKit
import Foundation
import Observation

/// An observable model that loads, decrypts, and manages the user's two-factor accounts.
///
/// Entries are fetched from the server and decrypted with the unlocked vault
/// key. Views compute codes from the decrypted accounts.
@Observable
final class TwoFactorViewModel {
    /// The session that provides the vault key.
    ///
    /// Read on each use, so a lock or a changed master password takes effect immediately.
    private let session: VaultSession

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

    /// Creates a view model that reads the vault key from the given session.
    init(session: VaultSession) {
        self.session = session
    }
}

// MARK: - Public functions
extension TwoFactorViewModel {
    /// Loads entries from the server and decrypts them.
    ///
    /// Signs the user out if the server rejects their token.
    func refresh(auth: AuthManager) async {
        guard auth.isSignedIn else {
            reset()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let entries = try await MuninService(tokenProvider: auth.tokenProvider).entries()
            let vault = try unlockedVault()
            decrypt(entries, key: vault.key, userID: vault.userID)
            errorMessage = nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch where Task.isCancelled {
            // URLSession reports a cancelled task as a network error.
            return
        } catch let error where error.isMuninAuthRejection {
            auth.signOut()
            reset()
        } catch {
            errorMessage = error.muninDescription
            hasLoaded = true
        }
    }

    /// Encrypts and uploads accounts, skipping exact duplicates.
    ///
    /// - Returns: The number of accounts added.
    /// - Throws: An error if the vault is locked, or if encryption or an upload fails.
    @discardableResult
    func add(_ accounts: [OTPAccount], auth: AuthManager) async throws -> Int {
        let vault = try unlockedVault()
        let key = vault.key
        let userID = vault.userID
        let service = MuninService(tokenProvider: auth.tokenProvider)
        var added = 0
        for account in accounts where !items.contains(where: { $0.account == account }) {
            let ciphertext = try VaultCrypto.seal(account, key: key, userID: userID)
            let entry = try await service.createEntry(ciphertext: ciphertext)
            items.append(VaultItem(id: entry.id, account: account))
            added += 1
        }
        return added
    }

    /// Returns the accounts that aren't stored yet, with repeats removed.
    func newAccounts(in accounts: [OTPAccount]) -> [OTPAccount] {
        var seen = Set(items.map(\.account))
        return accounts.filter { seen.insert($0).inserted }
    }

    /// Deletes an entry on the server, using the master password proof, and removes it from the list.
    func delete(_ item: VaultItem, auth: AuthManager) async {
        do {
            let vault = try unlockedVault()
            try await MuninService(tokenProvider: auth.tokenProvider, proof: vault.proof).deleteEntry(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.muninDescription
        }
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

    /// Decrypts entries into ``items`` and counts those that fail.
    func decrypt(_ entries: [EncryptedEntry], key: SymmetricKey, userID: String) {
        var decrypted: [VaultItem] = []
        var failures = 0
        for entry in entries {
            if let account = try? VaultCrypto.open(entry.ciphertext, key: key, userID: userID) {
                decrypted.append(VaultItem(id: entry.id, account: account))
            } else {
                failures += 1
            }
        }
        items = decrypted
        undecryptableCount = failures
    }

    func reset() {
        items = []
        errorMessage = nil
        undecryptableCount = 0
        hasLoaded = false
    }
}

/// An error from a vault operation that requires a signed-in user and an unlocked key.
enum VaultError: LocalizedError {
    /// No user is signed in.
    case notSignedIn
    /// The vault is locked, so its key isn't available.
    case keyMissing

    /// A localized message describing the error.
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return Localized("errors.notSignedIn")
        case .keyMissing:  return Localized("errors.keyMissing")
        }
    }
}
