import CryptoKit
import Foundation

/// Wraps and unwraps the vault key with the master password and the recovery key.
///
/// Pure functions with no state: ``VaultSession`` decides when to call them
/// and talks to the server. Password derivation runs off the main actor,
/// because PBKDF2 is deliberately slow.
nonisolated enum VaultKeyCrypto {
    /// Unwraps the vault key with a master password.
    ///
    /// - Returns: The unlocked vault, or `nil` if the password is wrong.
    /// - Throws: An error if the record's key derivation parameters can't be read.
    static func unlock(_ record: VaultKeyRecord, password: String, userID: String) async throws -> UnlockedVault? {
        let keys = try await derive(password: password, parameters: try parameters(of: record))
        guard let key = try? MasterKey.unwrap(record.passwordWrappedKey, with: keys.wrappingKey, userID: userID, purpose: .password) else {
            return nil
        }
        return UnlockedVault(userID: userID, key: key, proof: keys.proof)
    }

    /// Verifies a master password against the record.
    ///
    /// - Returns: The password's derived keys, or `nil` if the password is wrong.
    static func verify(_ record: VaultKeyRecord, password: String, userID: String) async throws -> DerivedKeys? {
        let keys = try await derive(password: password, parameters: try parameters(of: record))
        guard (try? MasterKey.unwrap(record.passwordWrappedKey, with: keys.wrappingKey, userID: userID, purpose: .password)) != nil else {
            return nil
        }
        return keys
    }

    /// Verifies a recovery key against the record.
    ///
    /// - Returns: The vault key and the recovery proof, or `nil` if the
    ///   recovery key is invalid or doesn't belong to this vault.
    static func recover(_ record: VaultKeyRecord, recoveryString: String, userID: String) -> (key: SymmetricKey, proof: String)? {
        guard let key = VaultKeyStore.key(fromRecoveryString: recoveryString) else { return nil }
        let keys = MasterKey.derive(recoveryKey: key)
        guard let unwrapped = try? MasterKey.unwrap(record.recoveryWrappedKey, with: keys.wrappingKey, userID: userID, purpose: .recovery),
              unwrapped.withUnsafeBytes({ Data($0) }) == key.withUnsafeBytes({ Data($0) }) else { return nil }
        return (key, keys.proof)
    }

    /// Wraps a vault key with a new master password, using a fresh salt, and
    /// with the recovery key.
    ///
    /// - Parameters:
    ///   - key: The vault key.
    ///   - password: The new master password.
    ///   - userID: The vault owner's user ID.
    ///   - currentProof: The proof that authorizes replacing an existing key, if any.
    ///   - parameters: The key derivation parameters. Tests pass fewer rounds.
    /// - Returns: The request body and the new password proof.
    static func makeVaultKeyBody(
        key: SymmetricKey,
        password: String,
        userID: String,
        currentProof: String?,
        parameters: KDFParameters = .new()
    ) async throws -> (VaultKeyRequestBody, String) {
        let passwordKeys = try await derive(password: password, parameters: parameters)
        let recoveryKeys = MasterKey.derive(recoveryKey: key)
        let body = VaultKeyRequestBody(
            passwordWrappedKey: try MasterKey.wrap(key, with: passwordKeys.wrappingKey, userID: userID, purpose: .password),
            recoveryWrappedKey: try MasterKey.wrap(key, with: recoveryKeys.wrappingKey, userID: userID, purpose: .recovery),
            kdf: String(decoding: try JSONEncoder().encode(parameters), as: UTF8.self),
            passwordProof: passwordKeys.proof,
            recoveryProof: recoveryKeys.proof,
            currentProof: currentProof
        )
        return (body, passwordKeys.proof)
    }

    /// Returns the record a successful save stores on the server.
    static func record(for body: VaultKeyRequestBody) -> VaultKeyRecord {
        VaultKeyRecord(passwordWrappedKey: body.passwordWrappedKey, recoveryWrappedKey: body.recoveryWrappedKey, kdf: body.kdf)
    }
}

nonisolated private extension VaultKeyCrypto {
    /// Reads the record's key derivation parameters.
    static func parameters(of record: VaultKeyRecord) throws -> KDFParameters {
        try JSONDecoder().decode(KDFParameters.self, from: Data(record.kdf.utf8))
    }

    /// Derives the wrapping key and proof from a master password, off the main actor.
    static func derive(password: String, parameters: KDFParameters) async throws -> DerivedKeys {
        try await Task.detached(priority: .userInitiated) {
            try MasterKey.derive(password: password, parameters: parameters)
        }.value
    }
}
