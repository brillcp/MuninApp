import Foundation
import Observation

/// An observable model that loads, decrypts, and manages the user's password items.
///
/// Each item's name, URL, and username are decrypted on load for listing and
/// searching. The password and note stay encrypted in memory until needed.
/// The main window and the macOS menu bar share a single instance.
///
/// Creates, edits, and deletes show in the list immediately and are saved in
/// the background. ``clear()`` cancels saves still in flight.
@Observable
final class VaultViewModel {
    private static let sortDefaultsKey = "munin.vault.sort"
    /// The section letters in ascending order: #, A–Z, then Å, Ä, and Ö.
    private static let sectionLetters = ["#"] + "ABCDEFGHIJKLMNOPQRSTUVWXYZÅÄÖ".map(String.init)
    /// The number of items an import uploads at the same time.
    private static let importConcurrency = 4

    /// The session that provides the vault key.
    ///
    /// Read on each use, so a lock or a changed master password takes effect immediately.
    private let session: VaultSession
    private let api: any MuninAPI
    private let user: any UserSession
    private let defaults: UserDefaults
    /// Encrypted passwords fetched during an unlock, so the list can appear as
    /// soon as the unlock succeeds. Consumed once by ``refresh()``.
    private var prefetchTask: Task<[EncryptedPassword], any Error>?
    /// Saves running in the background, keyed by an identifier for each save.
    private var saveTasks: [UUID: Task<Void, Never>] = [:]

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
    var sortOrder: [KeyPathComparator<PasswordItem>] {
        didSet {
            recomputeVisibleItems()
            saveSortOrder()
        }
    }
    /// The identifier of the selected item.
    var selection: PasswordItem.ID? {
        didSet { recomputeSelectedItem() }
    }

    /// Creates a view model.
    ///
    /// - Parameters:
    ///   - session: The session that provides the vault key.
    ///   - api: The API that stores the encrypted items.
    ///   - user: The signed-in user.
    ///   - defaults: The user defaults that store the sort order.
    init(session: VaultSession, api: any MuninAPI, user: any UserSession, defaults: UserDefaults = .standard) {
        self.session = session
        self.api = api
        self.user = user
        self.defaults = defaults
        sortOrder = Self.savedSortOrder(in: defaults)
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

    /// Removes all decrypted data and cancels saves in flight, for example
    /// when the vault locks or the user signs out.
    func clear() {
        saveTasks.values.forEach { $0.cancel() }
        saveTasks.removeAll()
        discardPrefetch()
        items = []
        selection = nil
        searchText = ""
        errorMessage = nil
        hasLoaded = false
    }

    /// Starts fetching encrypted passwords while an unlock is in progress.
    ///
    /// The passwords stay encrypted until ``refresh()`` decrypts them after
    /// the unlock succeeds. When the user is signed out, any pending prefetch
    /// is discarded.
    func prefetch() {
        guard user.isSignedIn else {
            prefetchTask = nil
            return
        }
        let api = api
        prefetchTask = Task { try await api.passwords() }
    }

    /// Cancels and discards a pending prefetch, for example after an unlock fails.
    func discardPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    /// Loads items from the server and decrypts their name, URL, and username
    /// off the main actor.
    ///
    /// Uses prefetched passwords when available. Items that fail to decrypt
    /// are counted in ``errorMessage``.
    func refresh() async {
        guard user.isSignedIn else { return }
        do {
            let vault = try unlockedVault()
            let encrypted: [EncryptedPassword]
            if let prefetched = prefetchTask, let value = try? await prefetched.value {
                encrypted = value
            } else {
                encrypted = try await api.passwords()
            }
            prefetchTask = nil
            let decoded = await VaultDecoder.passwordItems(from: encrypted, vault: vault)
            // The vault may have locked while the items were decrypting.
            guard session.vault?.userID == vault.userID else { return }
            items = decoded.items
            AutoFillIdentities.replaceAll(with: items)
            errorMessage = decoded.failures > 0 ? Localized("vault.undecryptable", decoded.failures) : nil
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
    func create(_ fields: PasswordFields) throws {
        let vault = try unlockedVault()
        let body = try VaultDecoder.seal(fields, vault: vault)
        let placeholder = PasswordItem(
            id: UUID(), name: fields.name, url: fields.url, username: fields.username,
            encryptedPassword: body.password, encryptedNote: body.note, lastUpdated: .now
        )
        items.append(placeholder)
        let api = api
        runInBackground { [weak self] in
            do {
                let saved = VaultDecoder.passwordItem(from: try await api.createPassword(body), fields: fields)
                guard let self, !Task.isCancelled else { return }
                if let index = items.firstIndex(where: { $0.id == placeholder.id }) { items[index] = saved }
                AutoFillIdentities.save([saved])
                if selection == placeholder.id { selection = saved.id }
            } catch {
                guard let self, !Task.isCancelled else { return }
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

    /// Encrypts and uploads each new row in the plan, a few at a time.
    ///
    /// Saved items join the list together when the import ends, so the list
    /// is sorted once rather than after every item. Stops at the first
    /// failure and reports it in ``errorMessage``.
    ///
    /// - Returns: The number of items saved.
    func runImport(_ plan: ImportPlan) async -> Int {
        let total = plan.newItems.count
        importProgress = (0, total)
        defer { importProgress = nil }
        let saved: [PasswordItem]
        do {
            saved = try await upload(plan.newItems)
        } catch let failure as ImportFailure {
            saved = failure.saved
            errorMessage = failure.error.muninDescription
        } catch {
            saved = []
            errorMessage = error.muninDescription
        }
        items.append(contentsOf: saved)
        AutoFillIdentities.save(saved)
        return saved.count
    }

    /// Updates an item in the list immediately and saves the change to the server in the background.
    ///
    /// The request includes the master password proof. If saving fails, the
    /// original item is restored and ``failureMessage`` describes the error.
    ///
    /// - Throws: An error if the fields can't be encrypted.
    func update(_ item: PasswordItem, with fields: PasswordFields) throws {
        let vault = try unlockedVault()
        let body = try VaultDecoder.seal(fields, vault: vault)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let original = items[index]
        items[index] = PasswordItem(
            id: item.id, name: fields.name, url: fields.url, username: fields.username,
            encryptedPassword: body.password, encryptedNote: body.note, lastUpdated: .now
        )
        let api = api
        runInBackground { [weak self] in
            do {
                let saved = VaultDecoder.passwordItem(from: try await api.updatePassword(id: item.id, body, proof: vault.proof), fields: fields)
                guard let self, !Task.isCancelled else { return }
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = saved }
                AutoFillIdentities.replace(original, with: saved)
            } catch {
                guard let self, !Task.isCancelled else { return }
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = original }
                failureMessage = error.muninDescription
            }
        }
    }

    /// Removes an item from the list immediately and deletes it on the server in the background.
    ///
    /// The request includes the master password proof. If deletion fails, the
    /// item is restored and ``failureMessage`` describes the error.
    func delete(_ item: PasswordItem) {
        guard let vault = try? unlockedVault(),
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if selection == item.id { selection = nil }
        items.remove(at: index)
        let api = api
        runInBackground { [weak self] in
            do {
                try await api.deletePassword(id: item.id, proof: vault.proof)
                guard self != nil, !Task.isCancelled else { return }
                AutoFillIdentities.remove([item])
            } catch {
                guard let self, !Task.isCancelled else { return }
                items.insert(item, at: min(index, items.count))
                failureMessage = error.muninDescription
            }
        }
    }

    /// Copies the item's decrypted password and updates its last-updated date.
    func copyPassword(_ item: PasswordItem) async {
        do {
            let vault = try unlockedVault()
            Pasteboard.copySensitive(try VaultDecoder.open(item.encryptedPassword, .password, vault: vault))

            let touched = try await api.touchPassword(id: item.id)
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
    func editDraft(for item: PasswordItem) -> EditDraft? {
        guard let password = try? decrypt(item.encryptedPassword, field: .password),
              let note = try? decrypt(item.encryptedNote, field: .note) else { return nil }
        return EditDraft(item: item, fields: PasswordFields(
            name: item.name, url: item.url, username: item.username, password: password, note: note
        ))
    }

    /// Decrypts a single encrypted field, such as the password or note.
    func decrypt(_ ciphertext: String, field: PasswordField) throws -> String {
        try VaultDecoder.open(ciphertext, field, vault: try unlockedVault())
    }
}

// MARK: - Private functions
private extension VaultViewModel {
    /// The items an import saved before one failed, and the failure.
    nonisolated struct ImportFailure: Error {
        let saved: [PasswordItem]
        let error: any Error
    }

    /// Runs a save in the background and keeps it until it ends, so
    /// ``clear()`` can cancel it.
    func runInBackground(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        saveTasks[id] = Task { [weak self] in
            await operation()
            self?.saveTasks[id] = nil
        }
    }

    /// Encrypts and uploads rows, ``importConcurrency`` at a time, updating
    /// ``importProgress`` as each finishes.
    ///
    /// - Returns: The saved items, in the order they finished.
    /// - Throws: An ``ImportFailure`` with the items saved before the first error.
    func upload(_ rows: [PasswordFields]) async throws -> [PasswordItem] {
        let vault = try unlockedVault()
        let bodies = try rows.map { try VaultDecoder.seal($0, vault: vault) }
        let api = api
        var saved: [PasswordItem] = []
        var firstError: (any Error)?
        await withTaskGroup(of: Result<PasswordItem, any Error>.self) { group in
            var next = 0
            func addNext() {
                guard next < rows.count else { return }
                let (fields, body) = (rows[next], bodies[next])
                next += 1
                group.addTask {
                    do {
                        return .success(VaultDecoder.passwordItem(from: try await api.createPassword(body), fields: fields))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for _ in 0..<Self.importConcurrency { addNext() }
            for await result in group {
                switch result {
                case .success(let item):
                    saved.append(item)
                    importProgress = (saved.count, rows.count)
                    if firstError == nil { addNext() }
                case .failure(let error):
                    if firstError == nil {
                        firstError = error
                        group.cancelAll()
                    }
                }
            }
        }
        if let firstError { throw ImportFailure(saved: saved, error: firstError) }
        return saved
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
        defaults.set(key, forKey: Self.sortDefaultsKey)
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
    static func savedSortOrder(in defaults: UserDefaults) -> [KeyPathComparator<PasswordItem>] {
        switch defaults.string(forKey: sortDefaultsKey) {
        case "name.reverse": [KeyPathComparator(\PasswordItem.name, order: .reverse)]
        case "lastUpdated": [KeyPathComparator(\PasswordItem.lastUpdated)]
        case "lastUpdated.reverse": [KeyPathComparator(\PasswordItem.lastUpdated, order: .reverse)]
        default: [KeyPathComparator(\PasswordItem.name)]
        }
    }
}
