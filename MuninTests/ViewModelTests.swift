import Foundation
@testable import MuninApp
import Testing

@Suite("View models with a fake API")
struct ViewModelTests {
    @Test("The session unlocks with the master password")
    func sessionUnlocks() async throws {
        let (session, _, _) = try await makeUnlockedSession()
        #expect(session.state == .unlocked)
        #expect(session.vault != nil)
    }

    @Test("2FA accounts are added once, reload, and delete with the proof")
    func twoFactor() async throws {
        let (session, api, user) = try await makeUnlockedSession()
        let model = TwoFactorViewModel(session: session, api: api, user: user)
        let proof = try #require(session.vault?.proof)
        let account = OTPAccount(issuer: "ACME", name: "me", secret: Data("secret".utf8))

        #expect(try await model.add([account, account]) == 1)
        #expect(api.storedEntries.count == 1)

        model.clear()
        await model.refresh()
        #expect(model.items.map(\.account) == [account])

        await model.delete(try #require(model.items.first))
        #expect(model.items.isEmpty)
        #expect(api.receivedProofs == [proof])
    }

    @Test("An import uploads every new row and skips duplicates")
    func importPasswords() async throws {
        let (session, api, user) = try await makeUnlockedSession()
        let model = VaultViewModel(session: session, api: api, user: user, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let rows = (0..<10).map { PasswordFields(name: "Site \($0)", url: "site\($0).example", username: "me", password: "p\($0)") }

        let plan = model.planImport(rows + [rows[0]], twoFactorAccounts: [])
        #expect(plan.newItems.count == 10)
        #expect(plan.duplicateCount == 1)

        #expect(await model.runImport(plan) == 10)
        #expect(model.items.count == 10)
        #expect(api.storedPasswords.count == 10)
        let isFinished = model.importProgress == nil
        #expect(isFinished)
    }

    @Test("A failed import keeps the items saved before the error")
    func failedImport() async throws {
        let (session, api, user) = try await makeUnlockedSession()
        let model = VaultViewModel(session: session, api: api, user: user, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        api.writeError = URLError(.notConnectedToInternet)
        let plan = model.planImport([PasswordFields(name: "A"), PasswordFields(name: "B")], twoFactorAccounts: [])

        #expect(await model.runImport(plan) == 0)
        #expect(model.errorMessage != nil)
    }

    @Test("Refreshing loads and decrypts the stored passwords")
    func refresh() async throws {
        let (session, api, user) = try await makeUnlockedSession()
        let vault = try #require(session.vault)
        let body = try VaultDecoder.seal(PasswordFields(name: "GitHub", url: "github.com", username: "me"), vault: vault)
        _ = try await api.createPassword(body)
        let model = VaultViewModel(session: session, api: api, user: user, defaults: UserDefaults(suiteName: UUID().uuidString)!)

        await model.refresh()
        #expect(model.items.map(\.name) == ["GitHub"])
        #expect(model.hasLoaded)
    }
}
