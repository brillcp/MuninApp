import CryptoKit
import Foundation
@testable import MuninApp
import Testing

@Suite("VaultCrypto")
struct VaultCryptoTests {
    let key = SymmetricKey(size: .bits256)
    let account = OTPAccount(issuer: "ACME", name: "me", secret: Data("foobar".utf8), digits: 8, period: 60, algorithm: .sha512)

    @Test("Round-trips a code entry")
    func accountRoundTrip() throws {
        let sealed = try VaultCrypto.seal(account, key: key, userID: "user-1")
        #expect(try VaultCrypto.open(sealed, key: key, userID: "user-1") == account)
    }

    @Test("Round-trips a password field, including empty and non-ASCII values", arguments: ["hunter2", "", "pässwörd 🔐"])
    func fieldRoundTrip(_ value: String) throws {
        let sealed = try VaultCrypto.seal(value, field: .password, key: key, userID: "user-1")
        #expect(try VaultCrypto.open(sealed, field: .password, key: key, userID: "user-1") == value)
    }

    @Test("Uses a fresh nonce for every seal")
    func freshNonce() throws {
        let first = try VaultCrypto.seal("same", field: .password, key: key, userID: "user-1")
        let second = try VaultCrypto.seal("same", field: .password, key: key, userID: "user-1")
        #expect(first != second)
    }

    @Test("Treats the user ID case-insensitively")
    func userIDCase() throws {
        let sealed = try VaultCrypto.seal(account, key: key, userID: "User-1")
        #expect(try VaultCrypto.open(sealed, key: key, userID: "user-1") == account)
    }

    @Test("Fails with the wrong key")
    func wrongKey() throws {
        let sealed = try VaultCrypto.seal(account, key: key, userID: "user-1")
        #expect(throws: (any Error).self) { try VaultCrypto.open(sealed, key: SymmetricKey(size: .bits256), userID: "user-1") }
    }

    @Test("Fails for another user")
    func wrongUser() throws {
        let sealed = try VaultCrypto.seal(account, key: key, userID: "user-1")
        #expect(throws: (any Error).self) { try VaultCrypto.open(sealed, key: key, userID: "user-2") }
    }

    @Test("Fails for another field")
    func wrongField() throws {
        let sealed = try VaultCrypto.seal("hunter2", field: .password, key: key, userID: "user-1")
        #expect(throws: (any Error).self) { try VaultCrypto.open(sealed, field: .note, key: key, userID: "user-1") }
    }

    @Test("Keeps code entries and password fields apart")
    func domainSeparation() throws {
        let sealed = try VaultCrypto.seal("{}", field: .password, key: key, userID: "user-1")
        #expect(throws: (any Error).self) { try VaultCrypto.open(sealed, key: key, userID: "user-1") }
    }

    @Test("Fails when the ciphertext is tampered with")
    func tampered() throws {
        let sealed = try VaultCrypto.seal("hunter2", field: .password, key: key, userID: "user-1")
        var bytes = try #require(Data(base64Encoded: sealed))
        bytes[bytes.count / 2] ^= 0x01
        #expect(throws: (any Error).self) {
            try VaultCrypto.open(bytes.base64EncodedString(), field: .password, key: key, userID: "user-1")
        }
    }

    @Test("Rejects input that isn't base64")
    func notBase64() {
        #expect(throws: VaultCrypto.CryptoError.invalidCiphertext) {
            try VaultCrypto.open("not base64!", field: .password, key: key, userID: "user-1")
        }
        #expect(throws: VaultCrypto.CryptoError.invalidCiphertext) {
            try VaultCrypto.open("not base64!", key: key, userID: "user-1")
        }
    }
}
