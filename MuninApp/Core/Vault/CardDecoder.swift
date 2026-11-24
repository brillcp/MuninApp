import Foundation

/// Converts between the server's encrypted card records and the decrypted
/// cards the app works with.
///
/// Bulk decoding runs off the main actor.
nonisolated enum CardDecoder {
    /// Decrypts the name, cardholder, and last four digits of each card
    /// record, off the main actor.
    ///
    /// The number, expiry date, security code, and note stay encrypted.
    static func items(from records: [EncryptedCard], vault: UnlockedVault) async -> VaultDecoder.Decoded<CardItem> {
        await Task.detached(priority: .userInitiated) {
            var items: [CardItem] = []
            items.reserveCapacity(records.count)
            var failures = 0
            for record in records {
                if let item = try? Self.item(from: record, vault: vault) {
                    items.append(item)
                } else {
                    failures += 1
                }
            }
            return VaultDecoder.Decoded(items: items, failures: failures)
        }.value
    }

    /// Decrypts a card record's name, cardholder, and last four digits.
    static func item(from record: EncryptedCard, vault: UnlockedVault) throws -> CardItem {
        let number = try open(record.number, .number, vault: vault)
        return CardItem(
            id: record.id,
            name: try open(record.name, .name, vault: vault),
            holder: try open(record.holder, .holder, vault: vault),
            lastDigits: CardFields(number: number).lastDigits,
            encryptedNumber: record.number,
            encryptedExpiry: record.expiry,
            encryptedCVV: record.cvv,
            encryptedNote: record.note,
            lastUpdated: record.updatedAt
        )
    }

    /// Returns the card a saved record describes, using the fields that were
    /// sealed into it, so the record doesn't need to be decrypted again.
    static func item(from record: EncryptedCard, fields: CardFields) -> CardItem {
        CardItem(
            id: record.id, name: fields.name, holder: fields.holder, lastDigits: fields.lastDigits,
            encryptedNumber: record.number, encryptedExpiry: record.expiry,
            encryptedCVV: record.cvv, encryptedNote: record.note, lastUpdated: record.updatedAt
        )
    }

    /// Encrypts each field separately, binding its ciphertext to the field.
    static func seal(_ fields: CardFields, vault: UnlockedVault) throws -> CardFieldsBody {
        func seal(_ value: String, _ field: CardField) throws -> String {
            try VaultCrypto.seal(value, field: field, key: vault.key, userID: vault.userID)
        }
        return CardFieldsBody(
            name: try seal(fields.name, .name),
            holder: try seal(fields.holder, .holder),
            number: try seal(fields.number, .number),
            expiry: try seal(fields.expiry, .expiry),
            cvv: try seal(fields.cvv, .cvv),
            note: try seal(fields.note, .note)
        )
    }

    /// Decrypts one field of a card, such as its number or security code.
    static func open(_ ciphertext: String, _ field: CardField, vault: UnlockedVault) throws -> String {
        try VaultCrypto.open(ciphertext, field: field, key: vault.key, userID: vault.userID)
    }
}
