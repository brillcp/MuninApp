import Foundation

/// One authenticator entry. This is what gets encrypted; Munin never sees it.
nonisolated struct OTPAccount: Codable, Sendable, Hashable {
    /// The HMAC hash function used to compute codes.
    enum Algorithm: String, Codable, Sendable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    /// The service, for example "GitHub". May be empty.
    var issuer: String
    /// The account at the service, usually a username or email.
    var name: String
    /// The shared secret, decoded from Base32.
    var secret: Data
    /// Digits per code.
    var digits: Int = 6
    /// Seconds each code is valid for.
    var period: Int = 30
    /// The HMAC hash function.
    var algorithm: Algorithm = .sha1

    /// Title shown in the list: the issuer, or the account name if there's none.
    var title: String { issuer.isEmpty ? name : issuer }
    /// Second line in the list: the account name, when the title is the issuer.
    var subtitle: String? { issuer.isEmpty ? nil : name }
}

/// A decrypted entry and its id on the server.
nonisolated struct VaultItem: Identifiable, Hashable {
    /// The entry's id on Munin.
    let id: UUID
    /// The decrypted account.
    let account: OTPAccount
}
