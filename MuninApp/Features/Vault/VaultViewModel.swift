import CryptoKit
import Foundation
import Observation

@Observable
final class VaultViewModel {
    /// Read at use time, so a changed master password (new proof) and a lock are picked up.
    private let session: VaultSession

    init(session: VaultSession) {
        self.session = session
    }

    private func unlockedVault() throws -> UnlockedVault {
        guard let vault = session.vault else { throw VaultError.keyMissing }
        return vault
    }

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
        do {
            let vault = try unlockedVault()
            let (key, userID) = (vault.key, vault.userID)
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
            errorMessage = failures > 0 ? Localized("vault.undecryptable", failures) : nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch where Task.isCancelled {
            // URLSession reports a cancelled task as a network error.
            return
        } catch {
            errorMessage = error.muninDescription
            hasLoaded = true
        }
    }

    // MARK: - Create

    func create(_ fields: PasswordFields, auth: AuthManager) async throws {
        let vault = try unlockedVault()
        let (key, userID) = (vault.key, vault.userID)
        let body = try Self.seal(fields, key: key, userID: userID)
        let saved = try await MuninService(tokenProvider: auth.tokenProvider).createPassword(body)
        items.append(try Self.item(from: saved, key: key, userID: userID))
    }

    // MARK: - Import

    /// Rows from a CSV that aren't in the vault yet, and how many were already there.
    struct ImportPlan: Identifiable {
        let id = UUID()
        let newItems: [PasswordFields]
        let duplicateCount: Int
    }

    /// Progress while importing, e.g. 12 of 79.
    private(set) var importProgress: (done: Int, total: Int)?

    /// Same name, username and website as an existing item (or an earlier row) counts as a duplicate.
    func planImport(_ rows: [PasswordFields]) -> ImportPlan {
        func key(_ name: String, _ username: String, _ url: String) -> String {
            [name, username, url].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.joined(separator: "\u{1F}")
        }
        var seen = Set(items.map { key($0.name, $0.username, $0.url) })
        var newItems: [PasswordFields] = []
        for row in rows where seen.insert(key(row.name, row.username, row.url)).inserted {
            newItems.append(row)
        }
        return ImportPlan(newItems: newItems, duplicateCount: rows.count - newItems.count)
    }

    /// Encrypts and uploads each row like a manually created item. Returns how many were saved.
    func runImport(_ plan: ImportPlan, auth: AuthManager) async -> Int {
        importProgress = (0, plan.newItems.count)
        defer { importProgress = nil }
        var saved = 0
        for fields in plan.newItems {
            do {
                try await create(fields, auth: auth)
                saved += 1
            } catch {
                errorMessage = error.muninDescription
                break
            }
            importProgress = (saved, plan.newItems.count)
        }
        return saved
    }

    // MARK: - Edit

    func update(_ item: PasswordItem, with fields: PasswordFields, auth: AuthManager) async throws {
        let vault = try unlockedVault()
        let (key, userID) = (vault.key, vault.userID)
        let body = try Self.seal(fields, key: key, userID: userID)
        let saved = try await MuninService(tokenProvider: auth.tokenProvider, proof: vault.proof).updatePassword(id: item.id, body)
        let updated = try Self.item(from: saved, key: key, userID: userID)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = updated
        }
    }

    // MARK: - Delete

    func delete(_ item: PasswordItem, auth: AuthManager) async {
        do {
            let vault = try unlockedVault()
            try await MuninService(tokenProvider: auth.tokenProvider, proof: vault.proof).deletePassword(id: item.id)
            if selection == item.id { selection = nil }
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.muninDescription
        }
    }

    // MARK: - Copy

    /// Decrypts the password just long enough to copy it, then bumps last updated.
    func copyPassword(_ item: PasswordItem, auth: AuthManager) async {
        do {
            let vault = try unlockedVault()
            let (key, userID) = (vault.key, vault.userID)
            Pasteboard.copySensitive(try VaultCrypto.open(item.encryptedPassword, field: "password", key: key, userID: userID))

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
        let vault = try unlockedVault()
        let (key, userID) = (vault.key, vault.userID)
        return try VaultCrypto.open(ciphertext, field: field, key: key, userID: userID)
    }

    // MARK: - Helpers

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
