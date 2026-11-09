import CryptoKit
import Foundation
@testable import MuninApp
import Testing

@Suite("VaultKeyCrypto")
struct VaultKeyCryptoTests {
    let key = SymmetricKey(size: .bits256)

    private func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    private func makeRecord(password: String) async throws -> (VaultKeyRecord, String) {
        let (body, proof) = try await VaultKeyCrypto.makeVaultKeyBody(key: key, password: password, userID: "user-1", currentProof: nil, parameters: fastKDF)
        return (VaultKeyCrypto.record(for: body), proof)
    }

    @Test("Unlocks with the right master password")
    func unlock() async throws {
        let (record, proof) = try await makeRecord(password: "correct horse")
        let vault = try #require(try await VaultKeyCrypto.unlock(record, password: "correct horse", userID: "user-1"))
        #expect(bytes(vault.key) == bytes(key))
        #expect(vault.proof == proof)
    }

    @Test("Rejects a wrong master password")
    func wrongPassword() async throws {
        let (record, _) = try await makeRecord(password: "correct horse")
        let unlocked = try await VaultKeyCrypto.unlock(record, password: "wrong", userID: "user-1")
        let verified = try await VaultKeyCrypto.verify(record, password: "wrong", userID: "user-1")
        let isRejected = unlocked == nil && verified == nil
        #expect(isRejected)
    }

    @Test("Rejects another user's record")
    func otherUser() async throws {
        let (record, _) = try await makeRecord(password: "correct horse")
        let unlocked = try await VaultKeyCrypto.unlock(record, password: "correct horse", userID: "user-2")
        let isRejected = unlocked == nil
        #expect(isRejected)
    }

    @Test("Recovers the key with the recovery key only")
    func recover() async throws {
        let (record, _) = try await makeRecord(password: "correct horse")
        let recovered = try #require(VaultKeyCrypto.recover(record, recoveryString: VaultKeyStore.recoveryString(for: key), userID: "user-1"))
        #expect(bytes(recovered.key) == bytes(key))
        let otherKey = VaultKeyStore.recoveryString(for: SymmetricKey(size: .bits256))
        let isRejected = VaultKeyCrypto.recover(record, recoveryString: otherKey, userID: "user-1") == nil
        #expect(isRejected)
    }
}
