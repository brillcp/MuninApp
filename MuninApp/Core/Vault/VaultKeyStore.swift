import CryptoKit
import Foundation

/// The per-user vault key. Lives in iCloud Keychain (synchronizable), so it
/// reaches the user's other Apple devices without ever touching Munin.
enum VaultKeyStore {
    private static func account(userID: String) -> String { "vault.key.\(userID.lowercased())" }

    static func load(userID: String) -> SymmetricKey? {
        guard let data = KeychainService.loadSynced(account: account(userID: userID)), data.count == 32 else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    static func save(_ key: SymmetricKey, userID: String) {
        KeychainService.saveSynced(key.withUnsafeBytes { Data($0) }, account: account(userID: userID))
    }

    static func generate(userID: String) -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        save(key, userID: userID)
        return key
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

    static func key(fromRecoveryString string: String) -> SymmetricKey? {
        let compact = string.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: compact), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }
}
