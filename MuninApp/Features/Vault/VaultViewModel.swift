import CryptoKit
import Foundation
import Observation

@Observable
final class VaultViewModel {
    private(set) var items: [PasswordItem] = [] {
        didSet {
            recomputeVisibleItems()
            recomputeSelectedItem()
        }
    }
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false

    var searchText = "" {
        didSet { recomputeVisibleItems() }
    }
    var sortOrder = [KeyPathComparator(\PasswordItem.lastUpdated, order: .reverse)] {
        didSet { recomputeVisibleItems() }
    }
    var selection: PasswordItem.ID? {
        didSet { recomputeSelectedItem() }
    }

    /// `items` filtered by `searchText` and sorted by `sortOrder`.
    private(set) var visibleItems: [PasswordItem] = []
    private(set) var selectedItem: PasswordItem?

    /// The inspector shows while an item is selected; closing it deselects.
    var isInspectorPresented: Bool {
        get { selectedItem != nil }
        set { if !newValue { selection = nil } }
    }

    private func recomputeVisibleItems() {
        let filtered = searchText.isEmpty ? items : items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
        }
        visibleItems = filtered.sorted(using: sortOrder)
    }

    private func recomputeSelectedItem() {
        selectedItem = selection.flatMap { id in items.first { $0.id == id } }
    }

    // MARK: - Loading

    func refresh(auth: AuthManager) async {
        guard auth.isSignedIn else { return }
        defer { hasLoaded = true }
        do {
            let (key, userID) = try vaultKey(auth: auth)
            let encrypted = try await MuninService(tokenProvider: auth.tokenProvider).passwords()
            var decrypted: [PasswordItem] = []
            var failures = 0
            for entry in encrypted {
                if let item = try? Self.item(from: entry, key: key, userID: userID) {
                    decrypted.append(item)
                } else {
                    failures += 1
                }
            }
            items = decrypted
            errorMessage = failures > 0 ? "\(failures) items couldn't be decrypted with this device's key." : nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.muninDescription
        }
    }

    // MARK: - Create

    func create(_ fields: PasswordFields, auth: AuthManager) async throws {
        let (key, userID) = try vaultKey(auth: auth)
        let body = try Self.seal(fields, key: key, userID: userID)
        let saved = try await MuninService(tokenProvider: auth.tokenProvider).createPassword(body)
        items.append(try Self.item(from: saved, key: key, userID: userID))
    }

    // MARK: - Edit

    func update(_ item: PasswordItem, with fields: PasswordFields, auth: AuthManager) async throws {
        let (key, userID) = try vaultKey(auth: auth)
        let body = try Self.seal(fields, key: key, userID: userID)
        let saved = try await MuninService(tokenProvider: auth.tokenProvider).updatePassword(id: item.id, body)
        let updated = try Self.item(from: saved, key: key, userID: userID)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        }
    }

    // MARK: - Copy

    /// Decrypts the password just long enough to copy it, then bumps last updated.
    func copyPassword(_ item: PasswordItem, auth: AuthManager) async {
        do {
            let (key, userID) = try vaultKey(auth: auth)
            Pasteboard.copy(try VaultCrypto.open(item.encryptedPassword, field: "password", key: key, userID: userID))

            let touched = try await MuninService(tokenProvider: auth.tokenProvider).touchPassword(id: item.id)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].lastUpdated = touched.updatedAt
            }
        } catch {
            errorMessage = error.muninDescription
        }
    }

    // MARK: - Reveal

    /// Decrypts one encrypted field (password or note) for display.
    func decrypt(_ ciphertext: String, field: String, auth: AuthManager) throws -> String {
        let (key, userID) = try vaultKey(auth: auth)
        return try VaultCrypto.open(ciphertext, field: field, key: key, userID: userID)
    }

    // MARK: - Helpers

    private func vaultKey(auth: AuthManager) throws -> (SymmetricKey, String) {
        guard let userID = auth.userID else { throw VaultError.notSignedIn }
        guard let key = VaultKeyStore.load(userID: userID) else { throw VaultError.keyMissing }
        return (key, userID)
    }

    private static func seal(_ fields: PasswordFields, key: SymmetricKey, userID: String) throws -> PasswordFieldsBody {
        func seal(_ value: String, _ field: String) throws -> String {
            try VaultCrypto.seal(value, field: field, key: key, userID: userID)
        }
        return PasswordFieldsBody(
            name: try seal(fields.name, "name"),
            url: try seal(fields.url, "url"),
            username: try seal(fields.username, "username"),
            password: try seal(fields.password, "password"),
            note: try seal(fields.note, "note")
        )
    }

    private static func item(from entry: EncryptedPassword, key: SymmetricKey, userID: String) throws -> PasswordItem {
        PasswordItem(
            id: entry.id,
            name: try VaultCrypto.open(entry.name, field: "name", key: key, userID: userID),
            url: try VaultCrypto.open(entry.url, field: "url", key: key, userID: userID),
            username: try VaultCrypto.open(entry.username, field: "username", key: key, userID: userID),
            encryptedPassword: entry.password,
            encryptedNote: entry.note,
            lastUpdated: entry.updatedAt
        )
    }
}
