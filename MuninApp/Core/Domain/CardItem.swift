import Foundation

/// A stored card held in memory.
///
/// The name and cardholder are decrypted for display and search, along with
/// the last four digits of the number. The full number, expiry date, security
/// code, and note stay encrypted until needed.
nonisolated struct CardItem: Identifiable, Hashable, Sendable {
    /// The card's server identifier.
    let id: UUID
    /// The card's name, such as the bank or what it's used for.
    var name: String
    /// The name printed on the card.
    var holder: String
    /// The last four digits of the card number, or fewer if the number is shorter.
    var lastDigits: String
    /// The encrypted card number.
    var encryptedNumber: String
    /// The encrypted expiry date.
    var encryptedExpiry: String
    /// The encrypted security code.
    var encryptedCVV: String
    /// The encrypted note.
    var encryptedNote: String
    /// The date the card was last edited.
    var lastUpdated: Date
}

/// The decrypted field values of a card being edited.
///
/// Exists only while the editor is open, or while a card is being saved.
nonisolated struct CardFields: Sendable {
    /// The card's name.
    var name = ""
    /// The name printed on the card.
    var holder = ""
    /// The card number.
    var number = ""
    /// The expiry date, such as `08/29`.
    var expiry = ""
    /// The security code.
    var cvv = ""
    /// A free-form note.
    var note = ""
}

nonisolated extension CardFields {
    /// The last four digits of the number, ignoring spaces and dashes.
    var lastDigits: String {
        String(number.filter(\.isNumber).suffix(4))
    }
}

nonisolated extension CardItem {
    /// Returns a card number in groups of four digits, such as `4242 4242 4242 4242`.
    ///
    /// - Parameter number: The number, with or without separators.
    static func formatted(_ number: String) -> String {
        let digits = Array(number.filter(\.isNumber))
        return stride(from: 0, to: digits.count, by: 4)
            .map { String(digits[$0..<min($0 + 4, digits.count)]) }
            .joined(separator: " ")
    }
}
