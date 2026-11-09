import Foundation

/// A namespace for building plain-text exports of the vault.
///
/// The caller loads the encrypted records from the server, so the export
/// matches what's stored, and passes the data to the system save panel.
/// Nothing is written to disk here.
nonisolated enum VaultExporter {
    /// Returns the passwords as CSV with `name,url,username,password,note` columns.
    ///
    /// The app's own import reads this format, as do most password managers.
    ///
    /// - Throws: An error if a record can't be decrypted.
    static func passwordsCSV(from records: [EncryptedPassword], vault: UnlockedVault) throws -> Data {
        var lines = ["name,url,username,password,note"]
        for record in records {
            let fields = try VaultDecoder.fields(of: record, vault: vault)
            let values = [fields.name, fields.url, fields.username, fields.password, fields.note]
            lines.append(values.map(csvField).joined(separator: ","))
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// Returns the two-factor accounts as `otpauth://totp/…` links, one per line.
    ///
    /// Most authenticator apps can import this format.
    ///
    /// - Throws: An error if a record can't be decrypted.
    static func twoFactorLinks(from records: [EncryptedEntry], vault: UnlockedVault) throws -> Data {
        let links = try records.map { otpauthLink(for: try VaultDecoder.twoFactorItem(from: $0, vault: vault).account) }
        return Data((links.joined(separator: "\n") + "\n").utf8)
    }
}

nonisolated private extension VaultExporter {
    /// Returns a CSV field, quoted per RFC 4180 if it contains commas, quotes, or line breaks.
    static func csvField(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Returns the account as an `otpauth://totp/Issuer:name?secret=…` link.
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
