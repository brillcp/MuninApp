import CryptoKit
import Foundation
@testable import MuninApp
import Testing

@Suite("VaultDecoder")
struct VaultDecoderTests {
    let vault = UnlockedVault(userID: "user-1", key: SymmetricKey(size: .bits256), proof: "proof")
    let fields = PasswordFields(name: "GitHub", url: "github.com", username: "me", password: "hunter2", note: "line 1\nline 2")

    private func record(_ body: PasswordFieldsBody) -> EncryptedPassword {
        EncryptedPassword(id: UUID(), name: body.name, url: body.url, username: body.username, password: body.password, note: body.note, updatedAt: .now)
    }

    @Test("Decrypts the listed fields and keeps the password and note encrypted")
    func passwordItem() throws {
        let body = try VaultDecoder.seal(fields, vault: vault)
        let item = try VaultDecoder.passwordItem(from: record(body), vault: vault)
        #expect(item.name == "GitHub")
        #expect(item.url == "github.com")
        #expect(item.username == "me")
        #expect(item.encryptedPassword == body.password)
        #expect(try VaultDecoder.open(item.encryptedPassword, .password, vault: vault) == "hunter2")
        #expect(try VaultDecoder.open(item.encryptedNote, .note, vault: vault) == "line 1\nline 2")
    }

    @Test("Round-trips every field for exports")
    func allFields() throws {
        let decoded = try VaultDecoder.fields(of: record(try VaultDecoder.seal(fields, vault: vault)), vault: vault)
        #expect(decoded.name == fields.name)
        #expect(decoded.password == fields.password)
        #expect(decoded.note == fields.note)
    }

    @Test("Counts records sealed for another user as failures")
    func bulkFailures() async throws {
        let other = UnlockedVault(userID: "user-2", key: vault.key, proof: "proof")
        let records = [
            record(try VaultDecoder.seal(fields, vault: vault)),
            record(try VaultDecoder.seal(fields, vault: other)),
        ]
        let decoded = await VaultDecoder.passwordItems(from: records, vault: vault)
        #expect(decoded.items.count == 1)
        #expect(decoded.failures == 1)
    }

    @Test("Builds a saved item from its fields without decrypting")
    func savedItem() throws {
        let saved = record(try VaultDecoder.seal(fields, vault: vault))
        let item = VaultDecoder.passwordItem(from: saved, fields: fields)
        #expect(item.id == saved.id)
        #expect(item.name == fields.name)
        #expect(item.encryptedNote == saved.note)
    }

    @Test("Decrypts 2FA records")
    func twoFactor() async throws {
        let account = OTPAccount(issuer: "ACME", name: "me", secret: Data("secret".utf8))
        let entry = EncryptedEntry(id: UUID(), ciphertext: try VaultDecoder.seal(account, vault: vault))
        let decoded = await VaultDecoder.twoFactorItems(from: [entry, EncryptedEntry(id: UUID(), ciphertext: "bad")], vault: vault)
        #expect(decoded.items.map(\.account) == [account])
        #expect(decoded.failures == 1)
    }
}
