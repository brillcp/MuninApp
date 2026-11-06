import CryptoKit
import Foundation

/// End-to-end encryption for vault entries.
///
/// Entries are sealed with AES-256-GCM using a key that exists only on the
/// user's devices. The server stores the ciphertext and can't read it.
enum VaultCrypto {
    /// Errors that occur while sealing or opening.
    enum CryptoError: Error {
        /// The ciphertext isn't valid base64, or sealing produced no output.
        case invalidCiphertext
    }

    /// Returns associated data that binds a ciphertext to its owner, so an
    /// entry moved to another user's rows fails to decrypt.
    private static func associatedData(userID: String) -> Data {
        Data("munin.vault.v1:\(userID.lowercased())".utf8)
    }

    /// Encrypts a 2FA account as JSON for storage on the server.
    ///
    /// - Returns: The sealed box, base64-encoded.
    static func seal(_ account: OTPAccount, key: SymmetricKey, userID: String) throws -> String {
        let plaintext = try JSONEncoder().encode(account)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: associatedData(userID: userID))
        guard let combined = box.combined else { throw CryptoError.invalidCiphertext }
        return combined.base64EncodedString()
    }

    // MARK: - Password fields

    /// Returns associated data that binds a password field's ciphertext to its
    /// owner and column, so ciphertext can't move between users or fields.
    private static func passwordAssociatedData(field: String, userID: String) -> Data {
        Data("munin.password.v1:\(userID.lowercased()):\(field)".utf8)
    }

    /// Encrypts a password field.
    ///
    /// - Parameters:
    ///   - value: The plaintext value.
    ///   - field: The field name: `name`, `url`, `username`, `password`, or `note`.
    ///   - key: The vault key.
    ///   - userID: The owner's user ID.
    /// - Returns: The sealed box, base64-encoded.
    static func seal(_ value: String, field: String, key: SymmetricKey, userID: String) throws -> String {
        let box = try AES.GCM.seal(Data(value.utf8), using: key, authenticating: passwordAssociatedData(field: field, userID: userID))
        guard let combined = box.combined else { throw CryptoError.invalidCiphertext }
        return combined.base64EncodedString()
    }

    /// Decrypts a password field.
    ///
    /// - Throws: An error if the key, user, or field doesn't match.
    static func open(_ ciphertext: String, field: String, key: SymmetricKey, userID: String) throws -> String {
        guard let data = Data(base64Encoded: ciphertext) else { throw CryptoError.invalidCiphertext }
        let box = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(box, using: key, authenticating: passwordAssociatedData(field: field, userID: userID))
        return String(decoding: plaintext, as: UTF8.self)
    }

    // MARK: - Code entries

    /// Decrypts a 2FA account.
    ///
    /// - Throws: An error if the key or user doesn't match.
    static func open(_ ciphertext: String, key: SymmetricKey, userID: String) throws -> OTPAccount {
        guard let data = Data(base64Encoded: ciphertext) else { throw CryptoError.invalidCiphertext }
        let box = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(box, using: key, authenticating: associatedData(userID: userID))
        return try JSONDecoder().decode(OTPAccount.self, from: plaintext)
    }
}
