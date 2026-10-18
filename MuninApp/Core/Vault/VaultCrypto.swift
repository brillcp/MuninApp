import CryptoKit
import Foundation

/// End-to-end encryption for vault entries: AES-256-GCM with a key that only
/// exists on the user's devices. Munin stores the output and can't read it.
enum VaultCrypto {
    enum CryptoError: Error {
        case invalidCiphertext
    }

    /// Binds each ciphertext to its owner, so an entry moved to another
    /// user's rows on the server fails to decrypt instead of being accepted.
    private static func associatedData(userID: String) -> Data {
        Data("munin.vault.v1:\(userID.lowercased())".utf8)
    }

    static func seal(_ account: OTPAccount, key: SymmetricKey, userID: String) throws -> String {
        let plaintext = try JSONEncoder().encode(account)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: associatedData(userID: userID))
        guard let combined = box.combined else { throw CryptoError.invalidCiphertext }
        return combined.base64EncodedString()
    }

    // MARK: - Password fields

    /// Each password field is sealed on its own and bound to its owner and
    /// its column, so ciphertext can't be moved between users or fields.
    private static func passwordAssociatedData(field: String, userID: String) -> Data {
        Data("munin.password.v1:\(userID.lowercased()):\(field)".utf8)
    }

    static func seal(_ value: String, field: String, key: SymmetricKey, userID: String) throws -> String {
        let box = try AES.GCM.seal(Data(value.utf8), using: key, authenticating: passwordAssociatedData(field: field, userID: userID))
        guard let combined = box.combined else { throw CryptoError.invalidCiphertext }
        return combined.base64EncodedString()
    }

    static func open(_ ciphertext: String, field: String, key: SymmetricKey, userID: String) throws -> String {
        guard let data = Data(base64Encoded: ciphertext) else { throw CryptoError.invalidCiphertext }
        let box = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(box, using: key, authenticating: passwordAssociatedData(field: field, userID: userID))
        return String(decoding: plaintext, as: UTF8.self)
    }

    // MARK: - Code entries

    static func open(_ ciphertext: String, key: SymmetricKey, userID: String) throws -> OTPAccount {
        guard let data = Data(base64Encoded: ciphertext) else { throw CryptoError.invalidCiphertext }
        let box = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(box, using: key, authenticating: associatedData(userID: userID))
        return try JSONDecoder().decode(OTPAccount.self, from: plaintext)
    }
}
