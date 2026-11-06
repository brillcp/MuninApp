import CommonCrypto
import CryptoKit
import Foundation

/// The parameters that turn a master password into a key.
///
/// Stored as JSON alongside the wrapped vault key on the server, so every
/// device derives the same key.
nonisolated struct KDFParameters: Codable, Sendable {
    /// The supported algorithm, PBKDF2-HMAC-SHA256.
    static let pbkdf2SHA256 = "pbkdf2-sha256"
    /// The number of PBKDF2 rounds for new master passwords.
    static let defaultIterations = 600_000

    /// The name of the key derivation function, `pbkdf2-sha256`.
    let algorithm: String
    /// The number of PBKDF2 rounds.
    let iterations: Int
    /// The salt: 16 random bytes, base64-encoded.
    let salt: String

    /// Returns parameters for a new master password, with the default rounds and a fresh random salt.
    static func new() -> KDFParameters {
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        return KDFParameters(algorithm: pbkdf2SHA256, iterations: defaultIterations, salt: salt.base64EncodedString())
    }
}

/// The two keys derived from the master password or the recovery key.
nonisolated struct DerivedKeys: Sendable {
    /// The key that encrypts and decrypts the vault key. It never leaves the device.
    let wrappingKey: SymmetricKey
    /// A value sent to the server as proof of knowing the secret.
    ///
    /// The server stores only a bcrypt hash of it, and it can't be used to
    /// recover the password or the wrapping key.
    let proof: String
}

/// Key derivation and wrapping for the master password and recovery key.
///
/// - Master password → PBKDF2-HMAC-SHA256 → HKDF → wrapping key and proof.
/// - Recovery key → HKDF → wrapping key and proof.
nonisolated enum MasterKey {
    /// The secret a key was derived from.
    ///
    /// Included in the HKDF info and the wrapped key's associated data, so keys
    /// derived from different secrets are never interchangeable.
    enum Purpose: String {
        /// The user's master password.
        case password
        /// The vault's recovery key.
        case recovery
    }

    /// Errors that occur when deriving keys or unwrapping the vault key.
    enum MasterKeyError: Error {
        /// The stored KDF parameters name an unknown algorithm or are malformed.
        case unsupportedKDF
        /// PBKDF2 derivation failed.
        case derivationFailed
        /// The wrapped key isn't valid base64, AES-GCM, or 32 bytes.
        case invalidWrappedKey
    }

    /// Derives the wrapping key and proof from the master password.
    ///
    /// The password is Unicode-normalized first so it derives the same key on
    /// every device. Derivation is deliberately slow, so call this off the main
    /// actor.
    static func derive(password: String, parameters: KDFParameters) throws -> DerivedKeys {
        guard parameters.algorithm == KDFParameters.pbkdf2SHA256,
              parameters.iterations > 0,
              let salt = Data(base64Encoded: parameters.salt) else {
            throw MasterKeyError.unsupportedKDF
        }
        let passwordData = Data(password.precomposedStringWithCanonicalMapping.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { output in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(parameters.iterations),
                        output.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard status == Int32(kCCSuccess) else { throw MasterKeyError.derivationFailed }
        return split(SymmetricKey(data: derived), purpose: .password)
    }

    /// Derives the wrapping key and proof from the recovery key.
    ///
    /// The recovery key is already uniformly random, so it skips PBKDF2.
    static func derive(recoveryKey: SymmetricKey) -> DerivedKeys {
        split(recoveryKey, purpose: .recovery)
    }

    /// Expands one input into two independent keys, so the proof the server sees can't unwrap anything.
    private static func split(_ input: SymmetricKey, purpose: Purpose) -> DerivedKeys {
        let wrappingKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input,
            info: Data("munin.\(purpose.rawValue).wrap.v1".utf8),
            outputByteCount: 32
        )
        let proofKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input,
            info: Data("munin.\(purpose.rawValue).auth.v1".utf8),
            outputByteCount: 32
        )
        return DerivedKeys(
            wrappingKey: wrappingKey,
            proof: proofKey.withUnsafeBytes { Data($0) }.base64EncodedString()
        )
    }

    // MARK: - Wrapping the vault key

    /// The AES-GCM associated data for a wrapped vault key.
    ///
    /// Binds the ciphertext to the user and to the secret that wrapped it, so
    /// the two wrapped copies can't be swapped.
    private static func associatedData(userID: String, purpose: Purpose) -> Data {
        Data("munin.vaultkey.v1:\(userID.lowercased()):\(purpose.rawValue)".utf8)
    }

    /// Encrypts the vault key with a wrapping key using AES-GCM.
    ///
    /// - Returns: The sealed box, base64-encoded.
    static func wrap(_ vaultKey: SymmetricKey, with wrappingKey: SymmetricKey, userID: String, purpose: Purpose) throws -> String {
        let plaintext = vaultKey.withUnsafeBytes { Data($0) }
        let box = try AES.GCM.seal(plaintext, using: wrappingKey, authenticating: associatedData(userID: userID, purpose: purpose))
        guard let combined = box.combined else { throw MasterKeyError.invalidWrappedKey }
        return combined.base64EncodedString()
    }

    /// Decrypts a wrapped vault key.
    ///
    /// - Throws: An error if the wrapping key is wrong, such as from an incorrect master password or recovery key.
    static func unwrap(_ wrapped: String, with wrappingKey: SymmetricKey, userID: String, purpose: Purpose) throws -> SymmetricKey {
        guard let data = Data(base64Encoded: wrapped) else { throw MasterKeyError.invalidWrappedKey }
        let box = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(box, using: wrappingKey, authenticating: associatedData(userID: userID, purpose: purpose))
        guard plaintext.count == 32 else { throw MasterKeyError.invalidWrappedKey }
        return SymmetricKey(data: plaintext)
    }
}

/// An unlocked vault, held in memory only and cleared on lock and sign-out.
nonisolated struct UnlockedVault: Sendable {
    /// The vault owner's user ID.
    let userID: String
    /// The vault key, which encrypts every entry and password field.
    let key: SymmetricKey
    /// The master password proof, sent to authorize edits and deletions.
    let proof: String
}
