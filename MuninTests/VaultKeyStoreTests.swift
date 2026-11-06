import CryptoKit
import Foundation
@testable import MuninApp
import Testing

@Suite("Recovery key")
struct VaultKeyStoreTests {
    private func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    @Test("Formats the key as base64 in groups of four")
    func format() {
        let key = SymmetricKey(data: Data(repeating: 0, count: 32))
        let string = VaultKeyStore.recoveryString(for: key)
        #expect(string == "AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAAA AAA=")
    }

    @Test("Round-trips through the recovery string")
    func roundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let parsed = try #require(VaultKeyStore.key(fromRecoveryString: VaultKeyStore.recoveryString(for: key)))
        #expect(bytes(parsed) == bytes(key))
    }

    @Test("Accepts the key without spaces or with extra whitespace")
    func whitespace() throws {
        let key = SymmetricKey(size: .bits256)
        let string = VaultKeyStore.recoveryString(for: key)
        let compact = string.replacingOccurrences(of: " ", with: "")
        let messy = "  " + string.replacingOccurrences(of: " ", with: "\n  ") + "\t"
        #expect(try bytes(#require(VaultKeyStore.key(fromRecoveryString: compact))) == bytes(key))
        #expect(try bytes(#require(VaultKeyStore.key(fromRecoveryString: messy))) == bytes(key))
    }

    @Test("Rejects invalid recovery strings", arguments: [
        "",
        "not a key",
        Data(repeating: 1, count: 16).base64EncodedString(),
        Data(repeating: 1, count: 33).base64EncodedString(),
    ])
    func invalid(_ string: String) {
        #expect(VaultKeyStore.key(fromRecoveryString: string) == nil)
    }
}
