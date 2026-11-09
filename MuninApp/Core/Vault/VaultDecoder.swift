import CryptoKit
import Foundation

/// Converts between the server's encrypted records and the decrypted items
/// the app works with.
///
/// The app and the AutoFill extension share this type, so both read the
/// stored format the same way. Bulk decoding runs off the main actor.
nonisolated enum VaultDecoder {
    /// Items that decrypted, and how many records didn't.
    struct Decoded<Item: Sendable>: Sendable {
        /// The decrypted items, in the order of their records.
        let items: [Item]
        /// The number of records that couldn't be decrypted with the vault key.
        let failures: Int
    }

    // MARK: - Passwords

    /// Decrypts the name, URL, and username of each password record, off the main actor.
    ///
    /// Passwords and notes stay encrypted.
    static func passwordItems(from records: [EncryptedPassword], vault: UnlockedVault) async -> Decoded<PasswordItem> {
        await Task.detached(priority: .userInitiated) {
            Self.decode(records) { try Self.passwordItem(from: $0, vault: vault) }
        }.value
    }

    /// Decrypts a password record's name, URL, and username.
    ///
    /// The password and note stay encrypted.
    static func passwordItem(from record: EncryptedPassword, vault: UnlockedVault) throws -> PasswordItem {
        PasswordItem(
            id: record.id,
            name: try open(record.name, .name, vault: vault),
            url: try open(record.url, .url, vault: vault),
            username: try open(record.username, .username, vault: vault),
            encryptedPassword: record.password,
            encryptedNote: record.note,
            lastUpdated: record.updatedAt
        )
    }

    /// Returns the item a saved record describes, using the fields that were
    /// sealed into it, so the record doesn't need to be decrypted again.
    static func passwordItem(from record: EncryptedPassword, fields: PasswordFields) -> PasswordItem {
        PasswordItem(
            id: record.id, name: fields.name, url: fields.url, username: fields.username,
            encryptedPassword: record.password, encryptedNote: record.note, lastUpdated: record.updatedAt
        )
    }

    /// Encrypts each field separately, binding its ciphertext to the field.
    static func seal(_ fields: PasswordFields, vault: UnlockedVault) throws -> PasswordFieldsBody {
        func seal(_ value: String, _ field: PasswordField) throws -> String {
            try VaultCrypto.seal(value, field: field, key: vault.key, userID: vault.userID)
        }
        return PasswordFieldsBody(
            name: try seal(fields.name, .name),
            url: try seal(fields.url, .url),
            username: try seal(fields.username, .username),
            password: try seal(fields.password, .password),
            note: try seal(fields.note, .note)
        )
    }

    /// Decrypts every field of a password record, for exports.
    static func fields(of record: EncryptedPassword, vault: UnlockedVault) throws -> PasswordFields {
        PasswordFields(
            name: try open(record.name, .name, vault: vault),
            url: try open(record.url, .url, vault: vault),
            username: try open(record.username, .username, vault: vault),
            password: try open(record.password, .password, vault: vault),
            note: try open(record.note, .note, vault: vault)
        )
    }

    /// Decrypts one field of a password item, such as its password or note.
    static func open(_ ciphertext: String, _ field: PasswordField, vault: UnlockedVault) throws -> String {
        try VaultCrypto.open(ciphertext, field: field, key: vault.key, userID: vault.userID)
    }

    // MARK: - 2FA accounts

    /// Decrypts each 2FA record, off the main actor.
    static func twoFactorItems(from records: [EncryptedEntry], vault: UnlockedVault) async -> Decoded<VaultItem> {
        await Task.detached(priority: .userInitiated) {
            Self.decode(records) { try Self.twoFactorItem(from: $0, vault: vault) }
        }.value
    }

    /// Decrypts a 2FA record.
    static func twoFactorItem(from record: EncryptedEntry, vault: UnlockedVault) throws -> VaultItem {
        VaultItem(id: record.id, account: try VaultCrypto.open(record.ciphertext, key: vault.key, userID: vault.userID))
    }

    /// Encrypts a 2FA account for storage.
    static func seal(_ account: OTPAccount, vault: UnlockedVault) throws -> String {
        try VaultCrypto.seal(account, key: vault.key, userID: vault.userID)
    }
}

nonisolated private extension VaultDecoder {
    /// Decodes each record, counting those that fail.
    static func decode<Record, Item: Sendable>(_ records: [Record], _ transform: (Record) throws -> Item) -> Decoded<Item> {
        var items: [Item] = []
        items.reserveCapacity(records.count)
        var failures = 0
        for record in records {
            if let item = try? transform(record) {
                items.append(item)
            } else {
                failures += 1
            }
        }
        return Decoded(items: items, failures: failures)
    }
}
