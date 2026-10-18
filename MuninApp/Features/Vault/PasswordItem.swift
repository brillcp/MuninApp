import Foundation

/// A password item in memory. Name, URL and username are decrypted for the
/// table and search; password and note stay encrypted until they're needed.
nonisolated struct PasswordItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var username: String
    var encryptedPassword: String
    var encryptedNote: String
    var lastUpdated: Date
}

/// Plain field values while the editor is open. Only lives as long as the sheet.
struct PasswordFields {
    var name = ""
    var url = ""
    var username = ""
    var password = ""
    var note = ""
}
