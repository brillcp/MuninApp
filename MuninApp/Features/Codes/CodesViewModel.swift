import CryptoKit
import Foundation
import Observation

/// Loads the user's encrypted entries from Munin, decrypts them with the
/// unlocked vault key, and adds/removes entries. Codes are calculated in the
/// views from the decrypted accounts.
@Observable
final class CodesViewModel {
    private(set) var items: [VaultItem] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Entries that didn't decrypt with this device's key.
    private(set) var undecryptableCount = 0

    /// Read at use time, so a changed master password (new proof) and a lock are picked up.
    private let session: VaultSession

    init(session: VaultSession) {
        self.session = session
    }

    private func unlockedVault() throws -> UnlockedVault {
        guard let vault = session.vault else { throw VaultError.keyMissing }
        return vault
    }

    // MARK: - Loading

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

    private func decrypt(_ entries: [EncryptedEntry], key: SymmetricKey, userID: String) {
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

    // MARK: - Changes

    /// Encrypts and uploads accounts, skipping exact duplicates. Returns how many were added.
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

    func delete(_ item: VaultItem, auth: AuthManager) async {
        do {
            let vault = try unlockedVault()
            try await MuninService(tokenProvider: auth.tokenProvider, proof: vault.proof).deleteEntry(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.muninDescription
        }
    }

    private func reset() {
        items = []
        errorMessage = nil
        undecryptableCount = 0
        hasLoaded = false
    }
}

enum VaultError: LocalizedError {
    case notSignedIn
    case keyMissing

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return Localized("errors.notSignedIn")
        case .keyMissing:  return Localized("errors.keyMissing")
        }
    }
}
