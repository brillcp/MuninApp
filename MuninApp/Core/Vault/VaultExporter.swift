import Foundation

/// Builds plain-text exports of the vault, for moving to another app.
///
/// Everything is loaded from Munin and decrypted in memory, so the export
/// matches what's stored. Nothing is written to disk here; the caller hands
/// the data to the system's save panel.
enum VaultExporter {
    /// The passwords as CSV with `name,url,username,password,note` columns,
    /// the format Munin's own import reads, as do most password managers.
    static func passwordsCSV(vault: UnlockedVault, auth: AuthManager) async throws -> Data {
        let (key, userID) = (vault.key, vault.userID)
        let items = try await MuninService(tokenProvider: auth.tokenProvider).passwords()
        var lines = ["name,url,username,password,note"]
        for item in items {
            let fields = try [
                ("name", item.name), ("url", item.url), ("username", item.username),
                ("password", item.password), ("note", item.note),
            ].map { field, ciphertext in
                try VaultCrypto.open(ciphertext, field: field, key: key, userID: userID)
            }
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// The 2FA accounts, one `otpauth://totp/…` link per line, which most
    /// authenticator apps can import.
    static func twoFactorLinks(vault: UnlockedVault, auth: AuthManager) async throws -> Data {
        let entries = try await MuninService(tokenProvider: auth.tokenProvider).entries()
        let links = try entries.map { entry in
            otpauthLink(for: try VaultCrypto.open(entry.ciphertext, key: vault.key, userID: vault.userID))
        }
        return Data((links.joined(separator: "\n") + "\n").utf8)
    }
}

private extension VaultExporter {
    /// One CSV field, quoted if it has commas, quotes or line breaks (RFC 4180).
    static func csvField(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The account as an `otpauth://totp/Issuer:name?secret=…` link.
    static func otpauthLink(for account: OTPAccount) -> String {
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = "totp"
        components.path = "/" + (account.issuer.isEmpty ? account.name : "\(account.issuer):\(account.name)")
        var query = [URLQueryItem(name: "secret", value: Base32.encode(account.secret))]
        if !account.issuer.isEmpty {
            query.append(URLQueryItem(name: "issuer", value: account.issuer))
        }
        query += [
            URLQueryItem(name: "algorithm", value: account.algorithm.rawValue),
            URLQueryItem(name: "digits", value: String(account.digits)),
            URLQueryItem(name: "period", value: String(account.period)),
        ]
        components.queryItems = query
        return components.string ?? ""
    }
}
