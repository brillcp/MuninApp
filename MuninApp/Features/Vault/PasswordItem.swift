import Foundation

/// A password item held in memory.
///
/// The name, URL, and username are decrypted for display and search. The
/// password and note stay encrypted until needed.
nonisolated struct PasswordItem: Identifiable, Hashable {
    /// The item's server identifier.
    let id: UUID
    /// The item's name, typically the service it belongs to.
    var name: String
    /// The website, with or without a scheme.
    var url: String
    /// The username or email address for the website.
    var username: String
    /// The encrypted password.
    var encryptedPassword: String
    /// The encrypted note.
    var encryptedNote: String
    /// The date the item was last edited or its password last copied.
    var lastUpdated: Date
}

/// The decrypted field values of a password item being edited.
///
/// Exists only while the editor is open.
struct PasswordFields {
    /// The item's name.
    var name = ""
    /// The website.
    var url = ""
    /// The username or email address.
    var username = ""
    /// The password.
    var password = ""
    /// A free-form note.
    var note = ""
}

extension PasswordItem {
    /// The website's lowercase domain without a `www.` prefix, used for
    /// AutoFill.
    ///
    /// For example, `https://www.github.com/login` returns `github.com`. Returns
    /// `nil` if the URL has no host.
    var domain: String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let host = URL(string: trimmed)?.host ?? URL(string: "https://\(trimmed)")?.host
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
