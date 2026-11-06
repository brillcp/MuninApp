import Foundation

/// An authenticator account.
///
/// Encrypted on the device before it's stored; the server never sees it in plain text.
nonisolated struct OTPAccount: Codable, Sendable, Hashable {
    /// The HMAC hash function used to compute codes.
    enum Algorithm: String, Codable, Sendable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    /// The service that issued the account, such as “GitHub”; may be empty.
    var issuer: String
    /// The account name at the service, usually a username or email.
    var name: String
    /// The shared secret, decoded from Base32.
    var secret: Data
    /// The number of digits in each code.
    var digits: Int = 6
    /// The number of seconds each code is valid.
    var period: Int = 30
    /// The HMAC hash function.
    var algorithm: Algorithm = .sha1

    /// The display title: the issuer, or the account name if there's no issuer.
    var title: String { issuer.isEmpty ? name : issuer }
    /// The display subtitle: the account name when the title is the issuer.
    var subtitle: String? { issuer.isEmpty ? nil : name }
}

/// A decrypted account and its server identifier.
nonisolated struct VaultItem: Identifiable, Hashable {
    /// The entry's identifier on the server.
    let id: UUID
    /// The decrypted account.
    let account: OTPAccount
}
