import Foundation

/// One authenticator entry. This is what gets encrypted; Munin never sees it.
nonisolated struct OTPAccount: Codable, Sendable, Hashable {
    enum Algorithm: String, Codable, Sendable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    var issuer: String
    var name: String
    var secret: Data
    var digits: Int = 6
    var period: Int = 30
    var algorithm: Algorithm = .sha1

    /// Title shown in the list: the issuer, or the account name if there's none.
    var title: String { issuer.isEmpty ? name : issuer }
    var subtitle: String? { issuer.isEmpty ? nil : name }
}

/// A decrypted entry and its id on the server.
nonisolated struct VaultItem: Identifiable, Hashable {
    let id: UUID
    let account: OTPAccount
}
