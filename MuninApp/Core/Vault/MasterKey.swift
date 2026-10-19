import CommonCrypto
import CryptoKit
import Foundation

/// How the master password is turned into a key. Stored as JSON next to the
/// wrapped vault key on Munin, so another device can derive the same key.
nonisolated struct KDFParameters: Codable, Sendable {
    static let pbkdf2SHA256 = "pbkdf2-sha256"
    static let defaultIterations = 600_000

    let algorithm: String
    let iterations: Int
    /// 16 random bytes, base64.
    let salt: String

    static func new() -> KDFParameters {
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        return KDFParameters(algorithm: pbkdf2SHA256, iterations: defaultIterations, salt: salt.base64EncodedString())
    }
}

/// The two keys derived from the master password or the recovery key.
nonisolated struct DerivedKeys: Sendable {
    /// Encrypts and decrypts the vault key. Never leaves the device.
    let wrappingKey: SymmetricKey
    /// Sent to Munin as proof (X-Munin-Proof). Munin keeps a bcrypt hash of it;
    /// it can't be turned back into the password or the wrapping key.
    let proof: String
}

/// Master password and recovery key crypto.
///
/// Master password → PBKDF2-HMAC-SHA256 → HKDF → wrapping key + proof.
/// Recovery key (the vault key itself, as before) → HKDF → wrapping key + proof.
nonisolated enum MasterKey {
    enum Purpose: String {
        case password
        case recovery
    }

    enum MasterKeyError: Error {
        case unsupportedKDF
        case derivationFailed
        case invalidWrappedKey
    }

    /// Slow on purpose (~0.5 s). Call off the main actor.
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

    static func derive(recoveryKey: SymmetricKey) -> DerivedKeys {
        split(recoveryKey, purpose: .recovery)
    }

    /// Two independent keys from one input, so the proof Munin sees can't unwrap anything.
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

    /// Bound to the user and to which key wrapped it, so the two copies can't be swapped.
    private static func associatedData(userID: String, purpose: Purpose) -> Data {
        Data("munin.vaultkey.v1:\(userID.lowercased()):\(purpose.rawValue)".utf8)
    }

    static func wrap(_ vaultKey: SymmetricKey, with wrappingKey: SymmetricKey, userID: String, purpose: Purpose) throws -> String {
        let plaintext = vaultKey.withUnsafeBytes { Data($0) }
        let box = try AES.GCM.seal(plaintext, using: wrappingKey, authenticating: associatedData(userID: userID, purpose: purpose))
        guard let combined = box.combined else { throw MasterKeyError.invalidWrappedKey }
        return combined.base64EncodedString()
    }

    /// Throws if the wrapping key is wrong (wrong master password or recovery key).
    static func unwrap(_ wrapped: String, with wrappingKey: SymmetricKey, userID: String, purpose: Purpose) throws -> SymmetricKey {
        guard let data = Data(base64Encoded: wrapped) else { throw MasterKeyError.invalidWrappedKey }
        let box = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(box, using: wrappingKey, authenticating: associatedData(userID: userID, purpose: purpose))
        guard plaintext.count == 32 else { throw MasterKeyError.invalidWrappedKey }
        return SymmetricKey(data: plaintext)
    }
}

/// The vault while it's unlocked: in memory only, cleared on lock and sign out.
nonisolated struct UnlockedVault: Sendable {
    let userID: String
    let key: SymmetricKey
    /// The master password proof, sent with deletes and edits.
    let proof: String
}
