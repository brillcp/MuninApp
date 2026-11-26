import Foundation
import Observation

/// An observable model that loads, decrypts, and manages the user's stored cards.
///
/// Each card's name, cardholder, and last four digits are decrypted on load
/// for listing and searching. The number, expiry date, security code, and note
/// stay encrypted in memory until needed.
///
/// Creates, edits, and deletes show in the list immediately and are saved in
/// the background. ``clear()`` cancels saves still in flight.
@Observable
final class CardsViewModel {
    /// The session that provides the vault key.
    ///
    /// Read on each use, so a lock or a changed master password takes effect immediately.
    private let session: VaultSession
    /// The API that loads, saves, and deletes the cards.
    private let api: any MuninAPI
    /// The signed-in user, whose identifier scopes the cards.
    private let user: any UserSession
    /// Saves running in the background, keyed by an identifier for each save.
    private var saveTasks: [UUID: Task<Void, Never>] = [:]

    /// All cards, with the fields the list needs decrypted.
    private(set) var items: [CardItem] = [] {
        didSet {
            recomputeVisibleItems()
            recomputeSelectedItem()
        }
    }
    /// A description of the last error, or of how many cards couldn't be decrypted.
    private(set) var errorMessage: String?
    /// A Boolean value that indicates whether the first load has finished, successfully or not.
    private(set) var hasLoaded = false
    /// The ``items`` matching ``searchText``, sorted by name.
    private(set) var visibleItems: [CardItem] = []
    /// The card matching ``selection``, if it still exists.
    private(set) var selectedItem: CardItem?
    /// A description of why a create, edit, or delete couldn't be saved to the server.
    ///
    /// The change, already shown in the list, is reverted when this is set.
    var failureMessage: String?

    /// The search text that filters ``visibleItems`` by name and cardholder.
    var searchText = "" {
        didSet { recomputeVisibleItems() }
    }
    /// The identifier of the selected card.
    var selection: CardItem.ID? {
        didSet { recomputeSelectedItem() }
    }

    /// Creates a view model.
    ///
    /// - Parameters:
    ///   - session: The session that provides the vault key.
    ///   - api: The API that stores the encrypted cards.
    ///   - user: The signed-in user.
    init(session: VaultSession, api: any MuninAPI, user: any UserSession) {
        self.session = session
        self.api = api
        self.user = user
    }
}

// MARK: - Public functions
extension CardsViewModel {
    /// A card being edited, paired with its decrypted fields.
    struct EditDraft: Identifiable {
        /// The stored card.
        let item: CardItem
        /// The card's fields in plain text.
        let fields: CardFields
        /// The identifier of the stored card.
        var id: UUID { item.id }
    }

    /// Loads cards from the server and decrypts their name, cardholder, and
    /// last four digits off the main actor.
    ///
    /// Cards that fail to decrypt are counted in ``errorMessage``.
    func refresh() async {
        guard user.isSignedIn else { return }
        do {
            let vault = try unlockedVault()
            let encrypted = try await api.cards()
            let decoded = await CardDecoder.items(from: encrypted, vault: vault)
            // The vault may have locked while the cards were decrypting.
            guard session.vault?.userID == vault.userID else { return }
            items = decoded.items
            errorMessage = decoded.failures > 0 ? Localized("vault.undecryptable", decoded.failures) : nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch where Task.isCancelled {
            // A cancelled load isn't shown as an error.
            return
        } catch {
            errorMessage = error.muninDescription
            hasLoaded = true
        }
    }

    /// Adds a new card to the list immediately and saves it to the server in the background.
    ///
    /// The card has a temporary identifier until the server assigns one. If
    /// saving fails, the card is removed and ``failureMessage`` describes the error.
    ///
    /// - Throws: An error if the fields can't be encrypted.
    func create(_ fields: CardFields) throws {
        let vault = try unlockedVault()
        let body = try CardDecoder.seal(fields, vault: vault)
        let placeholder = CardItem(
            id: UUID(), name: fields.name, holder: fields.holder, lastDigits: fields.lastDigits,
            encryptedNumber: body.number, encryptedExpiry: body.expiry, encryptedCVV: body.cvv,
            encryptedNote: body.note, lastUpdated: .now
        )
        items.append(placeholder)
        let api = api
        runInBackground { [weak self] in
            do {
                let saved = CardDecoder.item(from: try await api.createCard(body), fields: fields)
                guard let self, !Task.isCancelled else { return }
                if let index = items.firstIndex(where: { $0.id == placeholder.id }) { items[index] = saved }
                if selection == placeholder.id { selection = saved.id }
            } catch {
                guard let self, !Task.isCancelled else { return }
                items.removeAll { $0.id == placeholder.id }
                if selection == placeholder.id { selection = nil }
                failureMessage = error.muninDescription
            }
        }
    }

    /// Updates a card in the list immediately and saves the change to the server in the background.
    ///
    /// The request includes the master password proof. If saving fails, the
    /// original card is restored and ``failureMessage`` describes the error.
    ///
    /// - Throws: An error if the fields can't be encrypted.
    func update(_ item: CardItem, with fields: CardFields) throws {
        let vault = try unlockedVault()
        let body = try CardDecoder.seal(fields, vault: vault)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let original = items[index]
        items[index] = CardItem(
            id: item.id, name: fields.name, holder: fields.holder, lastDigits: fields.lastDigits,
            encryptedNumber: body.number, encryptedExpiry: body.expiry, encryptedCVV: body.cvv,
            encryptedNote: body.note, lastUpdated: .now
        )
        let api = api
        runInBackground { [weak self] in
            do {
                let saved = CardDecoder.item(from: try await api.updateCard(id: item.id, body, proof: vault.proof), fields: fields)
                guard let self, !Task.isCancelled else { return }
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = saved }
            } catch {
                guard let self, !Task.isCancelled else { return }
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = original }
                failureMessage = error.muninDescription
            }
        }
    }

    /// Removes a card from the list immediately and deletes it on the server in the background.
    ///
    /// The request includes the master password proof. If deletion fails, the
    /// card is restored and ``failureMessage`` describes the error.
    func delete(_ item: CardItem) {
        guard let vault = try? unlockedVault(),
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if selection == item.id { selection = nil }
        items.remove(at: index)
        let api = api
        runInBackground { [weak self] in
            do {
                try await api.deleteCard(id: item.id, proof: vault.proof)
            } catch {
                guard let self, !Task.isCancelled else { return }
                items.insert(item, at: min(index, items.count))
                failureMessage = error.muninDescription
            }
        }
    }

    /// Returns the card with every field decrypted for editing.
    ///
    /// - Returns: The draft, or `nil` if the fields can't be decrypted, for
    ///   example while the vault is locked.
    func editDraft(for item: CardItem) -> EditDraft? {
        guard let number = try? decrypt(item.encryptedNumber, field: .number),
              let expiry = try? decrypt(item.encryptedExpiry, field: .expiry),
              let cvv = try? decrypt(item.encryptedCVV, field: .cvv),
              let note = try? decrypt(item.encryptedNote, field: .note) else { return nil }
        return EditDraft(item: item, fields: CardFields(
            name: item.name, holder: item.holder, number: number, expiry: expiry, cvv: cvv, note: note
        ))
    }

    /// Decrypts a single encrypted field, such as the number or security code.
    func decrypt(_ ciphertext: String, field: CardField) throws -> String {
        try CardDecoder.open(ciphertext, field, vault: try unlockedVault())
    }

    /// Decrypts and copies the card number or security code, which is cleared
    /// from the clipboard after a minute.
    func copySensitive(_ ciphertext: String, field: CardField) {
        do {
            Pasteboard.copySensitive(try decrypt(ciphertext, field: field).filter { !$0.isWhitespace })
        } catch {
            errorMessage = error.muninDescription
        }
    }

    /// Removes all decrypted data and cancels saves in flight, for example
    /// when the vault locks or the user signs out.
    func clear() {
        saveTasks.values.forEach { $0.cancel() }
        saveTasks.removeAll()
        items = []
        selection = nil
        searchText = ""
        errorMessage = nil
        hasLoaded = false
    }
}

// MARK: - Private functions
private extension CardsViewModel {
    /// Runs a save in the background and keeps it until it ends, so
    /// ``clear()`` can cancel it.
    func runInBackground(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        saveTasks[id] = Task { [weak self] in
            await operation()
            self?.saveTasks[id] = nil
        }
    }

    /// Returns the unlocked vault.
    ///
    /// - Throws: ``VaultError/keyMissing`` while the vault is locked.
    func unlockedVault() throws -> UnlockedVault {
        guard let vault = session.vault else { throw VaultError.keyMissing }
        return vault
    }

    /// Recomputes ``visibleItems``.
    ///
    /// It's stored rather than computed, so observers update only when the inputs change.
    func recomputeVisibleItems() {
        let filtered = searchText.isEmpty ? items : items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.holder.localizedCaseInsensitiveContains(searchText)
        }
        visibleItems = filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Updates ``selectedItem`` to match the selection.
    func recomputeSelectedItem() {
        selectedItem = selection.flatMap { id in items.first { $0.id == id } }
    }
}
