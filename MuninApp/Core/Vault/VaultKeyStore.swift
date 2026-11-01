import CryptoKit
import Foundation
import LocalAuthentication

/// Where the vault key lives on a device.
///
/// - Unlocked: in memory only (`UnlockedVault`).
/// - Face ID / Touch ID: a copy of the key and proof in this device's Keychain,
///   readable only after biometrics (`.biometryCurrentSet`), never synced.
/// - Legacy: before master passwords the key synced through iCloud Keychain.
///   It's read once to set up the master password, then deleted.
nonisolated enum VaultKeyStore {
    /// The outcome of unlocking with Face ID / Touch ID.
    enum BiometricResult: Sendable {
        /// The key and proof were read.
        case unlocked(UnlockedVault)
        /// No copy on this device yet, or biometrics changed since it was saved.
        case notAvailable
        /// The user dismissed the prompt.
        case canceled
        /// Authentication failed, or the stored copy couldn't be read.
        case failed
    }

    /// Keychain account of the legacy synced key.
    private static func legacyAccount(userID: String) -> String { "vault.key.\(userID.lowercased())" }
    /// Keychain account of the biometric copy.
    private static func biometricAccount(userID: String) -> String { "vault.unlock.\(userID.lowercased())" }

    // MARK: - Legacy (iCloud Keychain)

    /// The legacy synced vault key, if this device has one.
    static func loadLegacy(userID: String) -> SymmetricKey? {
        guard let data = KeychainService.loadSynced(account: legacyAccount(userID: userID)), data.count == 32 else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    /// Deletes the legacy synced key, on every device, once a master password is set.
    static func deleteLegacy(userID: String) {
        KeychainService.deleteSynced(account: legacyAccount(userID: userID))
    }

    // MARK: - Biometrics

    /// The biometric copy's format: the key and the proof, both base64.
    private struct StoredVault: Codable {
        let key: String
        let proof: String
    }

    /// Saves the key and proof behind Face ID / Touch ID on this device.
    @discardableResult
    static func saveForBiometrics(_ vault: UnlockedVault) -> Bool {
        let stored = StoredVault(key: vault.key.withUnsafeBytes { Data($0) }.base64EncodedString(), proof: vault.proof)
        guard let data = try? JSONEncoder().encode(stored) else { return false }
        return KeychainService.saveBiometric(data, account: biometricAccount(userID: vault.userID))
    }

    /// Shows the Face ID / Touch ID prompt. Blocks, so call off the main actor.
    static func loadWithBiometrics(userID: String, reason: String) -> BiometricResult {
        switch KeychainService.loadBiometric(account: biometricAccount(userID: userID), reason: reason) {
        case .success(let data):
            guard let stored = try? JSONDecoder().decode(StoredVault.self, from: data),
                  let keyData = Data(base64Encoded: stored.key), keyData.count == 32 else { return .failed }
            return .unlocked(UnlockedVault(userID: userID, key: SymmetricKey(data: keyData), proof: stored.proof))
        case .notFound:
            return .notAvailable
        case .canceled:
            return .canceled
        case .failed:
            return .failed
        }
    }

    /// Whether this device has a biometric copy of the user's key. Doesn't prompt.
    static func hasBiometric(userID: String) -> Bool {
        KeychainService.hasBiometric(account: biometricAccount(userID: userID))
    }

    /// Deletes this device's biometric copy.
    static func deleteBiometric(userID: String) {
        KeychainService.deleteBiometric(account: biometricAccount(userID: userID))
    }

    // MARK: - Recovery key

    /// Human-copyable form of the key, in groups of 4 characters.
    static func recoveryString(for key: SymmetricKey) -> String {
        let base64 = key.withUnsafeBytes { Data($0) }.base64EncodedString()
        return stride(from: 0, to: base64.count, by: 4).map { offset in
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(start, offsetBy: 4, limitedBy: base64.endIndex) ?? base64.endIndex
            return String(base64[start..<end])
        }.joined(separator: " ")
    }

    /// Parses a recovery key typed or pasted by the user, with or without spaces.
    static func key(fromRecoveryString string: String) -> SymmetricKey? {
        let compact = string.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: compact), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }
}
