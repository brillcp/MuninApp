import CryptoKit
import Foundation
import LocalAuthentication

/// Storage for the vault key on a device.
///
/// - Term Unlocked: The key lives in memory only, in ``UnlockedVault``.
/// - Term Biometric: A copy of the key and proof lives in the device's
///   Keychain, readable only after Face ID or Touch ID
///   (`.biometryCurrentSet`), and never syncs.
nonisolated enum VaultKeyStore {
    /// The outcome of unlocking with Face ID or Touch ID.
    enum BiometricResult: Sendable {
        /// The key and proof were read.
        case unlocked(UnlockedVault)
        /// The device has no copy, or its biometrics changed since the copy was saved.
        case notAvailable
        /// The user dismissed the prompt.
        case canceled
        /// Authentication failed, or the stored copy couldn't be read.
        case failed
    }

    /// The Keychain account of the biometric copy.
    private static func biometricAccount(userID: String) -> String { "vault.unlock.\(userID.lowercased())" }

    // MARK: - Biometrics

    /// The stored format of the biometric copy: the key and proof, base64-encoded.
    private struct StoredVault: Codable {
        let key: String
        let proof: String
    }

    /// Saves the key and proof on the device, protected by Face ID or Touch ID.
    @discardableResult
    static func saveForBiometrics(_ vault: UnlockedVault) -> Bool {
        let stored = StoredVault(key: vault.key.withUnsafeBytes { Data($0) }.base64EncodedString(), proof: vault.proof)
        guard let data = try? JSONEncoder().encode(stored) else { return false }
        return KeychainService.saveBiometric(data, account: biometricAccount(userID: vault.userID))
    }

    /// Reads the biometric copy, showing the Face ID or Touch ID prompt.
    ///
    /// This method blocks, so call it off the main actor.
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

    /// Returns a Boolean value that indicates whether the device has a biometric
    /// copy of the user's key, without prompting.
    static func hasBiometric(userID: String) -> Bool {
        KeychainService.hasBiometric(account: biometricAccount(userID: userID))
    }

    /// Deletes the device's biometric copy.
    static func deleteBiometric(userID: String) {
        KeychainService.deleteBiometric(account: biometricAccount(userID: userID))
    }

    // MARK: - Recovery key

    /// Returns the key as a recovery string in groups of four characters.
    static func recoveryString(for key: SymmetricKey) -> String {
        let base64 = key.withUnsafeBytes { Data($0) }.base64EncodedString()
        return stride(from: 0, to: base64.count, by: 4).map { offset in
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(start, offsetBy: 4, limitedBy: base64.endIndex) ?? base64.endIndex
            return String(base64[start..<end])
        }.joined(separator: " ")
    }

    /// Parses a recovery key that the user typed or pasted, with or without spaces.
    static func key(fromRecoveryString string: String) -> SymmetricKey? {
        let compact = string.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: compact), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }
}
