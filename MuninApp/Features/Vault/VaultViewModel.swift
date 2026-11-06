import CryptoKit
import Foundation
import Observation

/// An observable model that loads, decrypts, and manages the user's password items.
///
/// Each item's name, URL, and username are decrypted on load for listing and
/// searching. The password and note stay encrypted in memory until needed.
/// The main window and the macOS menu bar share a single instance.
@Observable
final class VaultViewModel {
    private static let sortDefaultsKey = "munin.vault.sort"
    /// The section letters in ascending order: #, A–Z, then Å, Ä, and Ö.
    private static let sectionLetters = ["#"] + "ABCDEFGHIJKLMNOPQRSTUVWXYZÅÄÖ".map(String.init)

    /// The session that provides the vault key.
    ///
    /// Read on each use, so a lock or a changed master password takes effect immediately.
    private let session: VaultSession
    /// Encrypted passwords fetched during an unlock, so the list can appear as
    /// soon as the unlock succeeds. Consumed once by ``refresh(auth:)``.
    private var prefetchTask: Task<[EncryptedPassword], any Error>?

    /// All password items, with the fields the list needs decrypted.
    private(set) var items: [PasswordItem] = [] {
        didSet {
            recomputeVisibleItems()
            recomputeSelectedItem()
        }
    }
    /// A description of the last error, or of how many items couldn't be decrypted.
    private(set) var errorMessage: String?
    /// A Boolean value that indicates whether the first load has finished, successfully or not.
    private(set) var hasLoaded = false
    /// The ``items`` matching ``searchText``, sorted by ``sortOrder``.
    private(set) var visibleItems: [PasswordItem] = []
    /// The ``visibleItems`` grouped into letter sections when sorted by title.
    ///
    /// Empty when sorted by date edited, which keeps the list flat.
    private(set) var sections: [LetterSection] = []
    /// The item matching ``selection``, if it still exists.
    private(set) var selectedItem: PasswordItem?
    /// The progress of a running import, as completed and total item counts.
    private(set) var importProgress: (done: Int, total: Int)?
    /// A description of why a create, edit, or delete couldn't be saved to the server.
    ///
    /// The change, already shown in the list, is reverted when this is set.
    var failureMessage: String?

    /// The search text that filters ``visibleItems`` by name and username.
    var searchText = "" {
        didSet { recomputeVisibleItems() }
    }
    /// The list's sort order, persisted in user defaults.
    ///
    /// Defaults to ascending by name.
    var sortOrder = VaultViewModel.savedSortOrder() {
        didSet {
            recomputeVisibleItems()
            saveSortOrder()
        }
    }
    /// The identifier of the selected item.
    var selection: PasswordItem.ID? {
        didSet { recomputeSelectedItem() }
    }

    /// Creates a view model that reads the vault key from the given session.
    init(session: VaultSession) {
        self.session = session
    }
}

// MARK: - Public functions
extension VaultViewModel {
    /// A column the list can be sorted by.
    enum SortColumn: Hashable {
        /// The item's name.
        case title
        /// When the item was last edited.
        case dateEdited
    }

    /// The result of comparing imported CSV rows against the vault.
    struct ImportPlan: Identifiable {
        /// The plan's unique identifier.
        let id = UUID()
        /// The rows that aren't in the vault yet.
        let newItems: [PasswordFields]
        /// The number of rows skipped as duplicates.
        let duplicateCount: Int
        /// The two-factor accounts from the file that aren't stored yet.
        let twoFactorAccounts: [OTPAccount]
    }

    /// An item being edited, paired with its decrypted fields.
    struct EditDraft: Identifiable {
        /// The stored item.
        let item: PasswordItem
        /// The item's fields in plain text.
        let fields: PasswordFields
        /// The identifier of the stored item.
        var id: UUID { item.id }
    }

    /// A section of the list, grouped by first letter when sorted by title.
    struct LetterSection: Identifiable {
        /// The section's letter: A–Z, Å, Ä, Ö, or # for digits and symbols.
        let letter: String
        /// The section's items, in the list's sort order.
        let items: [PasswordItem]
        /// The section's letter, which is unique within the list.
        var id: String { letter }
    }

    /// The column the list is sorted by.
    ///
    /// Setting this value keeps the current ``sortDirection``.
    var sortColumn: SortColumn {
        get { sortOrder.first?.keyPath == \PasswordItem.name as PartialKeyPath<PasswordItem> ? .title : .dateEdited }
        set { sortOrder = [Self.comparator(for: newValue, order: sortDirection)] }
    }

    /// The direction the list is sorted in.
    ///
    /// Setting this value keeps the current ``sortColumn``.
    var sortDirection: SortOrder {
        get { sortOrder.first?.order ?? .forward }
        set { sortOrder = [Self.comparator(for: sortColumn, order: newValue)] }
    }

    /// Removes all decrypted data, for example when the vault locks or the user signs out.
    func clear() {
        items = []
        selection = nil
        searchText = ""
        errorMessage = nil
        hasLoaded = false
    }

    /// Starts fetching encrypted passwords while an unlock is in progress.
    ///
    /// The passwords stay encrypted until ``refresh(auth:)`` decrypts them after
    /// the unlock succeeds. When the user is signed out, any pending prefetch
    /// is discarded.
    func prefetch(auth: AuthManager) {
        guard auth.isSignedIn else {
            prefetchTask = nil
            return
        }
        let service = MuninService(tokenProvider: auth.tokenProvider)
        prefetchTask = Task { try await service.passwords() }
    }

    /// Cancels and discards a pending prefetch, for example after an unlock fails.
    func discardPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    /// Loads items from the server and decrypts their name, URL, and username.
    ///
    /// Uses prefetched passwords when available. Items that fail to decrypt
    /// are counted in ``errorMessage``.
    func refresh(auth: AuthManager) async {
        guard auth.isSignedIn else { return }
        do {
            let vault = try unlockedVault()
            let (key, userID) = (vault.key, vault.userID)
            let encrypted: [EncryptedPassword]
            if let prefetched = prefetchTask, let value = try? await prefetched.value {
                encrypted = value
            } else {
                encrypted = try await MuninService(tokenProvider: auth.tokenProvider).passwords()
            }
            prefetchTask = nil
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
            AutoFillIdentities.update(items)
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

    /// Adds a new item to the list immediately and saves it to the server in the background.
    ///
    /// The item has a temporary identifier until the server assigns one. If
    /// saving fails, the item is removed and ``failureMessage`` describes the error.
    ///
    /// - Throws: An error if the fields can't be encrypted.
    func create(_ fields: PasswordFields, auth: AuthManager) throws {
        let vault = try unlockedVault()
        let (key, userID) = (vault.key, vault.userID)
        let body = try Self.seal(fields, key: key, userID: userID)
        let placeholder = PasswordItem(
            id: UUID(), name: fields.name, url: fields.url, username: fields.username,
            encryptedPassword: body.password, encryptedNote: body.note, lastUpdated: .now
        )
        items.append(placeholder)
        let service = MuninService(tokenProvider: auth.tokenProvider)
        Task {
            do {
                let saved = try Self.item(from: try await service.createPassword(body), key: key, userID: userID)
                if let index = items.firstIndex(where: { $0.id == placeholder.id }) { items[index] = saved }
                AutoFillIdentities.update(items)
                if selection == placeholder.id { selection = saved.id }
            } catch {
                items.removeAll { $0.id == placeholder.id }
                if selection == placeholder.id { selection = nil }
                failureMessage = error.muninDescription
            }
        }
    }

    /// Determines which imported rows are new.
    ///
    /// A row is a duplicate when its name, username, and website match an
    /// existing item or an earlier row, ignoring case and surrounding whitespace.
    ///
    /// - Parameters:
    ///   - rows: The rows parsed from the imported file.
    ///   - twoFactorAccounts: New two-factor accounts from the file, already
    ///     filtered against stored accounts. They're passed through unchanged.
    /// - Returns: The rows to import and the number of duplicates skipped.
    func planImport(_ rows: [PasswordFields], twoFactorAccounts: [OTPAccount]) -> ImportPlan {
        /// A case- and whitespace-insensitive key for duplicate checks.
        func key(_ name: String, _ username: String, _ url: String) -> String {
            [name, username, url].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.joined(separator: "\u{1F}")
        }
        var seen = Set(items.map { key($0.name, $0.username, $0.url) })
        var newItems: [PasswordFields] = []
        for row in rows where seen.insert(key(row.name, row.username, row.url)).inserted {
            newItems.append(row)
        }
        return ImportPlan(newItems: newItems, duplicateCount: rows.count - newItems.count, twoFactorAccounts: twoFactorAccounts)
    }

    /// Encrypts and uploads each new row in the plan.
    ///
    /// Stops at the first failure and reports it in ``errorMessage``.
    ///
    /// - Returns: The number of items saved.
    func runImport(_ plan: ImportPlan, auth: AuthManager) async -> Int {
        importProgress = (0, plan.newItems.count)
        defer { importProgress = nil }
        var saved = 0
        for fields in plan.newItems {
            do {
                try await upload(fields, auth: auth)
                saved += 1
            } catch {
                errorMessage = error.muninDescription
                break
            }
            importProgress = (saved, plan.newItems.count)
        }
        AutoFillIdentities.update(items)
        return saved
    }

    /// Updates an item in the list immediately and saves the change to the server in the background.
    ///
    /// The request includes the master password proof. If saving fails, the
    /// original item is restored and ``failureMessage`` describes the error.
    ///
    /// - Throws: An error if the fields can't be encrypted.
    func update(_ item: PasswordItem, with fields: PasswordFields, auth: AuthManager) throws {
        let vault = try unlockedVault()
        let (key, userID) = (vault.key, vault.userID)
        let body = try Self.seal(fields, key: key, userID: userID)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let original = items[index]
        items[index] = PasswordItem(
            id: item.id, name: fields.name, url: fields.url, username: fields.username,
            encryptedPassword: body.password, encryptedNote: body.note, lastUpdated: .now
        )
        let service = MuninService(tokenProvider: auth.tokenProvider, proof: vault.proof)
        Task {
            do {
                let saved = try Self.item(from: try await service.updatePassword(id: item.id, body), key: key, userID: userID)
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = saved }
                AutoFillIdentities.update(items)
            } catch {
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = original }
                failureMessage = error.muninDescription
            }
        }
    }

    /// Removes an item from the list immediately and deletes it on the server in the background.
    ///
    /// The request includes the master password proof. If deletion fails, the
    /// item is restored and ``failureMessage`` describes the error.
    func delete(_ item: PasswordItem, auth: AuthManager) {
        guard let vault = try? unlockedVault(),
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if selection == item.id { selection = nil }
        items.remove(at: index)
        let service = MuninService(tokenProvider: auth.tokenProvider, proof: vault.proof)
        Task {
            do {
                try await service.deletePassword(id: item.id)
                AutoFillIdentities.update(items)
            } catch {
                items.insert(item, at: min(index, items.count))
                failureMessage = error.muninDescription
            }
        }
    }

    /// Copies the item's decrypted password and updates its last-updated date.
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

    /// Returns the item with its password and note decrypted for editing.
    ///
    /// - Returns: The draft, or `nil` if the fields can't be decrypted, for
    ///   example while the vault is locked.
    func editDraft(for item: PasswordItem, auth: AuthManager) -> EditDraft? {
        guard let password = try? decrypt(item.encryptedPassword, field: "password", auth: auth),
              let note = try? decrypt(item.encryptedNote, field: "note", auth: auth) else { return nil }
        return EditDraft(item: item, fields: PasswordFields(
            name: item.name, url: item.url, username: item.username, password: password, note: note
        ))
    }

    /// Decrypts a single encrypted field, such as the password or note.
    func decrypt(_ ciphertext: String, field: String, auth: AuthManager) throws -> String {
        let vault = try unlockedVault()
        let (key, userID) = (vault.key, vault.userID)
        return try VaultCrypto.open(ciphertext, field: field, key: key, userID: userID)
    }
}

// MARK: - Private functions
private extension VaultViewModel {
    /// Encrypts and saves a new item, adding it to the list once the server confirms it.
    func upload(_ fields: PasswordFields, auth: AuthManager) async throws {
        let vault = try unlockedVault()
        let (key, userID) = (vault.key, vault.userID)
        let body = try Self.seal(fields, key: key, userID: userID)
        let saved = try await MuninService(tokenProvider: auth.tokenProvider).createPassword(body)
        items.append(try Self.item(from: saved, key: key, userID: userID))
    }

    /// Returns the unlocked vault.
    ///
    /// - Throws: ``VaultError/keyMissing`` while the vault is locked.
    func unlockedVault() throws -> UnlockedVault {
        guard let vault = session.vault else { throw VaultError.keyMissing }
        return vault
    }

    /// Recomputes ``visibleItems`` and ``sections``.
    ///
    /// They're stored rather than computed, so observers update only when the inputs change.
    func recomputeVisibleItems() {
        let filtered = searchText.isEmpty ? items : items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
        }
        visibleItems = filtered.sorted(using: sortOrder)
        sections = sortColumn == .title ? Self.sections(for: visibleItems, order: sortDirection) : []
    }

    func recomputeSelectedItem() {
        selectedItem = selection.flatMap { id in items.first { $0.id == id } }
    }

    func saveSortOrder() {
        guard let primary = sortOrder.first else { return }
        let column = primary.keyPath == \PasswordItem.name as PartialKeyPath<PasswordItem> ? "name" : "lastUpdated"
        let key = primary.order == .reverse ? "\(column).reverse" : column
        UserDefaults.standard.set(key, forKey: Self.sortDefaultsKey)
    }

    /// Groups items into sections by the first letter of their name.
    ///
    /// Items keep their order within each section. Sections run #, A–Z, Å, Ä,
    /// Ö, and are reversed when the order is descending.
    static func sections(for items: [PasswordItem], order: SortOrder) -> [LetterSection] {
        let grouped = Dictionary(grouping: items, by: sectionLetter(for:))
        let letters = order == .reverse ? Array(sectionLetters.reversed()) : sectionLetters
        return letters.compactMap { letter in
            grouped[letter].map { LetterSection(letter: letter, items: $0) }
        }
    }

    /// Returns the section letter for an item.
    ///
    /// The letter is the name's uppercased first character, with diacritics
    /// removed except on Å, Ä, and Ö. Digits, symbols, other scripts, and
    /// empty names use #.
    static func sectionLetter(for item: PasswordItem) -> String {
        guard let first = item.name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let letter = String(first).uppercased()
        if ["Å", "Ä", "Ö"].contains(letter) { return letter }
        let folded = letter.folding(options: .diacriticInsensitive, locale: nil)
        return sectionLetters.contains(folded) ? folded : "#"
    }

    static func comparator(for column: SortColumn, order: SortOrder) -> KeyPathComparator<PasswordItem> {
        switch column {
        case .title: KeyPathComparator(\PasswordItem.name, order: order)
        case .dateEdited: KeyPathComparator(\PasswordItem.lastUpdated, order: order)
        }
    }

    /// Returns the persisted sort order, or ascending by name if none is saved.
    static func savedSortOrder() -> [KeyPathComparator<PasswordItem>] {
        switch UserDefaults.standard.string(forKey: sortDefaultsKey) {
        case "name.reverse": [KeyPathComparator(\PasswordItem.name, order: .reverse)]
        case "lastUpdated": [KeyPathComparator(\PasswordItem.lastUpdated)]
        case "lastUpdated.reverse": [KeyPathComparator(\PasswordItem.lastUpdated, order: .reverse)]
        default: [KeyPathComparator(\PasswordItem.name)]
        }
    }

    /// Encrypts each field separately, binding the ciphertext to the field's name.
    static func seal(_ fields: PasswordFields, key: SymmetricKey, userID: String) throws -> PasswordFieldsBody {
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

    /// Creates an item from its encrypted form, decrypting the name, URL, and username.
    ///
    /// The password and note stay encrypted.
    static func item(from entry: EncryptedPassword, key: SymmetricKey, userID: String) throws -> PasswordItem {
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
