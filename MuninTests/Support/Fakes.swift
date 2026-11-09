import CryptoKit
import Foundation
@testable import MuninApp

/// Key derivation parameters with few rounds, so tests stay fast.
let fastKDF = KDFParameters(algorithm: KDFParameters.pbkdf2SHA256, iterations: 1_000, salt: Data("0123456789abcdef".utf8).base64EncodedString())

/// A signed-in user that records sign-outs.
final class FakeUser: UserSession {
    var isSignedIn = true
    var userID: String? = "user-1"
    private(set) var signOutCount = 0

    func signOut() {
        signOutCount += 1
        isSignedIn = false
        userID = nil
    }
}

/// An in-memory Munin API.
final class FakeMuninAPI: MuninAPI {
    var record: VaultKeyRecord?
    var storedEntries: [EncryptedEntry] = []
    var storedPasswords: [EncryptedPassword] = []
    /// The proofs sent with each call that requires one.
    private(set) var receivedProofs: [String] = []
    /// The error every write throws, if set.
    var writeError: (any Error)?

    func entries() async throws -> [EncryptedEntry] { storedEntries }

    func createEntry(ciphertext: String) async throws -> EncryptedEntry {
        if let writeError { throw writeError }
        let entry = EncryptedEntry(id: UUID(), ciphertext: ciphertext)
        storedEntries.append(entry)
        return entry
    }

    func deleteEntry(id: UUID, proof: String) async throws {
        receivedProofs.append(proof)
        storedEntries.removeAll { $0.id == id }
    }

    func passwords() async throws -> [EncryptedPassword] { storedPasswords }

    func createPassword(_ body: PasswordFieldsBody) async throws -> EncryptedPassword {
        if let writeError { throw writeError }
        let saved = EncryptedPassword(
            id: UUID(), name: body.name, url: body.url, username: body.username,
            password: body.password, note: body.note, updatedAt: .now
        )
        storedPasswords.append(saved)
        return saved
    }

    func updatePassword(id: UUID, _ body: PasswordFieldsBody, proof: String) async throws -> EncryptedPassword {
        receivedProofs.append(proof)
        if let writeError { throw writeError }
        let saved = EncryptedPassword(
            id: id, name: body.name, url: body.url, username: body.username,
            password: body.password, note: body.note, updatedAt: .now
        )
        storedPasswords.removeAll { $0.id == id }
        storedPasswords.append(saved)
        return saved
    }

    func deletePassword(id: UUID, proof: String) async throws {
        receivedProofs.append(proof)
        if let writeError { throw writeError }
        storedPasswords.removeAll { $0.id == id }
    }

    func touchPassword(id: UUID) async throws -> EncryptedPassword {
        guard let stored = storedPasswords.first(where: { $0.id == id }) else { throw URLError(.fileDoesNotExist) }
        return stored
    }

    func vaultKey() async throws -> VaultKeyRecord? { record }

    func createVaultKey(_ body: VaultKeyRequestBody) async throws -> Bool {
        guard record == nil else { return false }
        record = VaultKeyCrypto.record(for: body)
        return true
    }

    func replaceVaultKey(_ body: VaultKeyRequestBody) async throws {
        record = VaultKeyCrypto.record(for: body)
    }

    func subscription() async throws -> SubscriptionStatus {
        SubscriptionStatus(required: false, active: true, billingIssue: nil)
    }

    func linkSubscription(transactionID: String) async throws -> SubscriptionStatus {
        try await subscription()
    }

    func deleteAccount(appleAuthorizationCode: String?, proof: String?) async throws {}
}

/// Returns a session unlocked with a fake API and a vault key wrapped by `password`.
///
/// - Returns: The session, the API, and the user.
func makeUnlockedSession(password: String = "correct horse") async throws -> (VaultSession, FakeMuninAPI, FakeUser) {
    let api = FakeMuninAPI()
    let user = FakeUser()
    let key = SymmetricKey(size: .bits256)
    let (body, _) = try await VaultKeyCrypto.makeVaultKeyBody(key: key, password: password, userID: "user-1", currentProof: nil, parameters: fastKDF)
    api.record = VaultKeyCrypto.record(for: body)
    let settings = VaultSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    let session = VaultSession(api: api, user: user, settings: settings, biometricsAvailable: false)
    await session.prepare()
    await session.unlock(masterPassword: password)
    return (session, api, user)
}
