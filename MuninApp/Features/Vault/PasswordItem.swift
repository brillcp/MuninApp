import Foundation

/// A password item in memory. Name, URL and username are decrypted for the
/// table and search; password and note stay encrypted until they're needed.
nonisolated struct PasswordItem: Identifiable, Hashable {
    /// The item's id on Munin.
    let id: UUID
    /// The item's name, for example the service.
    var name: String
    /// The website, with or without a scheme.
    var url: String
    /// The username or email for the site.
    var username: String
    /// The password, still encrypted.
    var encryptedPassword: String
    /// The note, still encrypted.
    var encryptedNote: String
    /// When the item was last edited, or its password last copied.
    var lastUpdated: Date
}

/// Plain field values while the editor is open. Only lives as long as the sheet.
struct PasswordFields {
    /// The item's name.
    var name = ""
    /// The website.
    var url = ""
    /// The username or email.
    var username = ""
    /// The password.
    var password = ""
    /// A free-form note.
    var note = ""
}
