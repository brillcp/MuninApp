import Foundation

/// Turns what a QR code or a pasted link contains into accounts:
/// - `otpauth://totp/Issuer:name?secret=…` (a site's 2FA setup QR code)
/// - `otpauth-migration://offline?data=…` (Google Authenticator export, many accounts)
enum OTPAuthParser {
    enum ParseError: LocalizedError, Equatable {
        case unsupported
        case hotpNotSupported
        case missingSecret
        case invalidSecret
        case invalidMigrationData

        var errorDescription: String? {
            switch self {
            case .unsupported:          return "That isn't an authenticator link or QR code."
            case .hotpNotSupported:     return "Counter-based (HOTP) codes aren't supported."
            case .missingSecret:        return "The link has no secret."
            case .invalidSecret:        return "The secret isn't valid Base32."
            case .invalidMigrationData: return "Couldn't read the Google Authenticator export."
            }
        }
    }

    static func parse(_ text: String) throws -> [OTPAccount] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased() else {
            throw ParseError.unsupported
        }
        switch scheme {
        case "otpauth":           return [try parseOTPAuth(components)]
        case "otpauth-migration": return try parseMigration(components)
        default:                  throw ParseError.unsupported
        }
    }

    // MARK: - otpauth://

    private static func parseOTPAuth(_ components: URLComponents) throws -> OTPAccount {
        switch components.host?.lowercased() {
        case "totp": break
        case "hotp": throw ParseError.hotpNotSupported
        default:     throw ParseError.unsupported
        }

        let query = Dictionary(
            (components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        guard let secretString = query["secret"], !secretString.isEmpty else { throw ParseError.missingSecret }
        guard let secret = Base32.decode(secretString) else { throw ParseError.invalidSecret }

        // Label: "Issuer:name" or "name" (already percent-decoded).
        let label = String(components.path.drop(while: { $0 == "/" }))
        var labelIssuer: String?
        var name = label
        if let colon = label.firstIndex(of: ":") {
            labelIssuer = String(label[..<colon])
            name = String(label[label.index(after: colon)...])
        }

        return OTPAccount(
            issuer: (query["issuer"] ?? labelIssuer ?? "").trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            secret: secret,
            digits: query["digits"].flatMap(Int.init) ?? 6,
            period: query["period"].flatMap(Int.init) ?? 30,
            algorithm: OTPAccount.Algorithm(rawValue: (query["algorithm"] ?? "SHA1").uppercased()) ?? .sha1
        )
    }

    // MARK: - otpauth-migration:// (protobuf)

    private static func parseMigration(_ components: URLComponents) throws -> [OTPAccount] {
        guard var base64 = components.queryItems?.first(where: { $0.name == "data" })?.value else {
            throw ParseError.invalidMigrationData
        }
        base64 = base64.replacingOccurrences(of: " ", with: "+")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let payload = Data(base64Encoded: base64) else { throw ParseError.invalidMigrationData }

        var accounts: [OTPAccount] = []
        for field in try Protobuf.fields(payload) where field.number == 1 {
            guard case .bytes(let otpData) = field.value else { continue }
            var account = OTPAccount(issuer: "", name: "", secret: Data())
            var type: UInt64 = 2
            for otpField in try Protobuf.fields(otpData) {
                switch (otpField.number, otpField.value) {
                case (1, .bytes(let data)): account.secret = data
                case (2, .bytes(let data)): account.name = String(decoding: data, as: UTF8.self)
                case (3, .bytes(let data)): account.issuer = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "+", with: " ")
                case (4, .varint(let value)): account.algorithm = [2: .sha256, 3: .sha512][value] ?? .sha1
                case (5, .varint(let value)): account.digits = value == 2 ? 8 : 6
                case (6, .varint(let value)): type = value
                default: break
                }
            }
            // type 1 = HOTP; skip those.
            if type != 1, !account.secret.isEmpty { accounts.append(account) }
        }
        guard !accounts.isEmpty else { throw ParseError.invalidMigrationData }
        return accounts
    }
}

/// Just enough protobuf to read Google Authenticator's MigrationPayload.
private enum Protobuf {
    enum Value { case varint(UInt64), bytes(Data), other }
    struct Field { let number: Int; let value: Value }

    static func fields(_ data: Data) throws -> [Field] {
        let bytes = [UInt8](data)
        var index = 0
        var fields: [Field] = []

        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard index < bytes.count, shift < 64 else { throw OTPAuthParser.ParseError.invalidMigrationData }
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
        }

        while index < bytes.count {
            let key = try varint()
            let number = Int(key >> 3)
            switch key & 7 {
            case 0:
                fields.append(Field(number: number, value: .varint(try varint())))
            case 2:
                let length = Int(try varint())
                guard length >= 0, index + length <= bytes.count else { throw OTPAuthParser.ParseError.invalidMigrationData }
                fields.append(Field(number: number, value: .bytes(Data(bytes[index..<index + length]))))
                index += length
            case 1:
                index += 8
                fields.append(Field(number: number, value: .other))
            case 5:
                index += 4
                fields.append(Field(number: number, value: .other))
            default:
                throw OTPAuthParser.ParseError.invalidMigrationData
            }
        }
        return fields
    }
}
