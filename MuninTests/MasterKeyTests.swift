import CryptoKit
import Foundation
@testable import MuninApp
import Testing

@Suite("MasterKey")
struct MasterKeyTests {
    /// Low iterations keep the tests fast; the algorithm is the same at any count.
    let parameters = KDFParameters(algorithm: KDFParameters.pbkdf2SHA256, iterations: 1_000, salt: Data("0123456789abcdef".utf8).base64EncodedString())

    private func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    @Test("Matches PBKDF2-HMAC-SHA256 followed by HKDF")
    func knownAnswer() throws {
        // The widely published PBKDF2-HMAC-SHA256("password", "salt", 4096, 32) vector.
        let pbkdf2 = Data([
            0xc5, 0xe4, 0x78, 0xd5, 0x92, 0x88, 0xc8, 0x41, 0xaa, 0x53, 0x0d, 0xb6, 0x84, 0x5c, 0x4c, 0x8d,
            0x96, 0x28, 0x93, 0xa0, 0x01, 0xce, 0x4e, 0x11, 0xa4, 0x96, 0x38, 0x73, 0xaa, 0x98, 0x13, 0x4a,
        ])
        let parameters = KDFParameters(algorithm: KDFParameters.pbkdf2SHA256, iterations: 4096, salt: Data("salt".utf8).base64EncodedString())
        let keys = try MasterKey.derive(password: "password", parameters: parameters)

        let input = SymmetricKey(data: pbkdf2)
        let wrapping = HKDF<SHA256>.deriveKey(inputKeyMaterial: input, info: Data("munin.password.wrap.v1".utf8), outputByteCount: 32)
        let auth = HKDF<SHA256>.deriveKey(inputKeyMaterial: input, info: Data("munin.password.auth.v1".utf8), outputByteCount: 32)
        #expect(bytes(keys.wrappingKey) == bytes(wrapping))
        #expect(keys.proof == bytes(auth).base64EncodedString())
    }

    @Test("Derives the same keys for the same input")
    func deterministic() throws {
        let first = try MasterKey.derive(password: "correct horse", parameters: parameters)
        let second = try MasterKey.derive(password: "correct horse", parameters: parameters)
        #expect(bytes(first.wrappingKey) == bytes(second.wrappingKey))
        #expect(first.proof == second.proof)
    }

    @Test("Keeps the wrapping key and the proof independent")
    func wrappingKeyIsNotProof() throws {
        let keys = try MasterKey.derive(password: "correct horse", parameters: parameters)
        #expect(bytes(keys.wrappingKey).base64EncodedString() != keys.proof)
    }

    @Test("Derives different keys for a different password or salt")
    func differentInput() throws {
        let base = try MasterKey.derive(password: "correct horse", parameters: parameters)
        let otherPassword = try MasterKey.derive(password: "correct horsf", parameters: parameters)
        let otherSalt = try MasterKey.derive(
            password: "correct horse",
            parameters: KDFParameters(algorithm: KDFParameters.pbkdf2SHA256, iterations: 1_000, salt: Data("fedcba9876543210".utf8).base64EncodedString())
        )
        #expect(base.proof != otherPassword.proof)
        #expect(base.proof != otherSalt.proof)
    }

    @Test("Normalizes Unicode in the password")
    func unicodeNormalization() throws {
        let composed = try MasterKey.derive(password: "caf\u{E9}", parameters: parameters)
        let decomposed = try MasterKey.derive(password: "cafe\u{301}", parameters: parameters)
        #expect(composed.proof == decomposed.proof)
    }

    @Test("Separates the password and recovery purposes")
    func purposes() throws {
        let input = SymmetricKey(size: .bits256)
        let recovery = MasterKey.derive(recoveryKey: input)
        let again = MasterKey.derive(recoveryKey: input)
        #expect(recovery.proof == again.proof)
        let wrappedForPassword = try MasterKey.wrap(input, with: recovery.wrappingKey, userID: "u", purpose: .password)
        #expect(throws: (any Error).self) {
            try MasterKey.unwrap(wrappedForPassword, with: recovery.wrappingKey, userID: "u", purpose: .recovery)
        }
    }

    @Test("Rejects unsupported KDF parameters", arguments: [
        KDFParameters(algorithm: "argon2id", iterations: 1, salt: "c2FsdA=="),
        KDFParameters(algorithm: KDFParameters.pbkdf2SHA256, iterations: 0, salt: "c2FsdA=="),
        KDFParameters(algorithm: KDFParameters.pbkdf2SHA256, iterations: 1, salt: "not base64!"),
    ])
    func unsupported(_ parameters: KDFParameters) {
        #expect(throws: MasterKey.MasterKeyError.unsupportedKDF) {
            try MasterKey.derive(password: "x", parameters: parameters)
        }
    }

    @Test("New parameters use PBKDF2-SHA256 with a random 128-bit salt")
    func newParameters() throws {
        let first = KDFParameters.new()
        let second = KDFParameters.new()
        #expect(first.algorithm == KDFParameters.pbkdf2SHA256)
        #expect(first.iterations == KDFParameters.defaultIterations)
        #expect(try #require(Data(base64Encoded: first.salt)).count == 16)
        #expect(first.salt != second.salt)
    }

    @Test("Wraps and unwraps the vault key")
    func wrapRoundTrip() throws {
        let vaultKey = SymmetricKey(size: .bits256)
        let wrappingKey = SymmetricKey(size: .bits256)
        let wrapped = try MasterKey.wrap(vaultKey, with: wrappingKey, userID: "User", purpose: .password)
        let unwrapped = try MasterKey.unwrap(wrapped, with: wrappingKey, userID: "user", purpose: .password)
        #expect(bytes(unwrapped) == bytes(vaultKey))
    }

    @Test("Fails to unwrap with the wrong key, user or purpose")
    func unwrapFailures() throws {
        let vaultKey = SymmetricKey(size: .bits256)
        let wrappingKey = SymmetricKey(size: .bits256)
        let wrapped = try MasterKey.wrap(vaultKey, with: wrappingKey, userID: "u1", purpose: .password)
        #expect(throws: (any Error).self) { try MasterKey.unwrap(wrapped, with: SymmetricKey(size: .bits256), userID: "u1", purpose: .password) }
        #expect(throws: (any Error).self) { try MasterKey.unwrap(wrapped, with: wrappingKey, userID: "u2", purpose: .password) }
        #expect(throws: (any Error).self) { try MasterKey.unwrap(wrapped, with: wrappingKey, userID: "u1", purpose: .recovery) }
        #expect(throws: MasterKey.MasterKeyError.invalidWrappedKey) { try MasterKey.unwrap("%%%", with: wrappingKey, userID: "u1", purpose: .password) }
    }

    @Test("Rejects a wrapped key that isn't 256 bits")
    func wrongKeySize() throws {
        let wrappingKey = SymmetricKey(size: .bits256)
        let wrapped = try MasterKey.wrap(SymmetricKey(size: .bits128), with: wrappingKey, userID: "u", purpose: .password)
        #expect(throws: MasterKey.MasterKeyError.invalidWrappedKey) {
            try MasterKey.unwrap(wrapped, with: wrappingKey, userID: "u", purpose: .password)
        }
    }
}
