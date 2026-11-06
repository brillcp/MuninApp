import Foundation
@testable import MuninApp
import Testing

@Suite("OTPAuthParser")
struct OTPAuthParserTests {
    @Test("Parses a full otpauth URL")
    func fullURL() throws {
        let accounts = try OTPAuthParser.parse(
            "otpauth://totp/ACME%20Co:john@example.com?secret=MZXW6YTBOI&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60"
        )
        #expect(accounts == [OTPAccount(
            issuer: "ACME Co", name: "john@example.com", secret: Data("foobar".utf8),
            digits: 8, period: 60, algorithm: .sha256
        )])
    }

    @Test("Uses defaults for missing parameters")
    func defaults() throws {
        let account = try #require(OTPAuthParser.parse("otpauth://totp/john?secret=MZXW6YTBOI").first)
        #expect(account.issuer.isEmpty)
        #expect(account.name == "john")
        #expect(account.digits == 6)
        #expect(account.period == 30)
        #expect(account.algorithm == .sha1)
    }

    @Test("Takes the issuer from the label when there's no issuer parameter")
    func issuerFromLabel() throws {
        let account = try #require(OTPAuthParser.parse("otpauth://totp/GitHub:octocat?secret=MZXW6YTBOI").first)
        #expect(account.issuer == "GitHub")
        #expect(account.name == "octocat")
    }

    @Test("Prefers the issuer parameter over the label")
    func issuerParameterWins() throws {
        let account = try #require(OTPAuthParser.parse("otpauth://totp/Old:octocat?secret=MZXW6YTBOI&issuer=New").first)
        #expect(account.issuer == "New")
        #expect(account.name == "octocat")
    }

    @Test("Ignores case in the scheme, type, parameter names and algorithm")
    func caseInsensitive() throws {
        let account = try #require(OTPAuthParser.parse("OTPAUTH://TOTP/x?SECRET=mzxw6ytboi&Algorithm=sha512").first)
        #expect(account.secret == Data("foobar".utf8))
        #expect(account.algorithm == .sha512)
    }

    @Test("Trims surrounding whitespace")
    func whitespace() throws {
        #expect(try OTPAuthParser.parse("  otpauth://totp/x?secret=MZXW6YTBOI\n").count == 1)
    }

    @Test("Falls back to SHA1 for an unknown algorithm")
    func unknownAlgorithm() throws {
        let account = try #require(OTPAuthParser.parse("otpauth://totp/x?secret=MZXW6YTBOI&algorithm=MD5").first)
        #expect(account.algorithm == .sha1)
    }

    @Test("Throws the matching error for invalid input", arguments: [
        ("https://example.com", OTPAuthParser.ParseError.unsupported),
        ("not a url at all", .unsupported),
        ("otpauth://foo/x?secret=MZXW6YTBOI", .unsupported),
        ("otpauth://hotp/x?secret=MZXW6YTBOI&counter=1", .hotpNotSupported),
        ("otpauth://totp/x", .missingSecret),
        ("otpauth://totp/x?secret=", .missingSecret),
        ("otpauth://totp/x?secret=1111", .invalidSecret),
        ("otpauth-migration://offline", .invalidMigrationData),
        ("otpauth-migration://offline?data=!!!", .invalidMigrationData),
    ])
    func errors(input: String, error: OTPAuthParser.ParseError) {
        #expect(throws: error) { try OTPAuthParser.parse(input) }
    }

    @Test("Parses a Google Authenticator migration link")
    func migration() throws {
        let payload = Protobuf.message([
            .bytes(1, Protobuf.message([
                .bytes(1, Data("foobar".utf8)),
                .bytes(2, Data("john@example.com".utf8)),
                .bytes(3, Data("ACME+Co".utf8)),
                .varint(4, 2),  // SHA256
                .varint(5, 2),  // 8 digits
                .varint(6, 2),  // TOTP
            ])),
            .bytes(1, Protobuf.message([
                .bytes(1, Data("hotp!".utf8)),
                .bytes(2, Data("counter".utf8)),
                .varint(6, 1),  // HOTP, skipped
            ])),
            .bytes(1, Protobuf.message([
                .bytes(1, Data("plain".utf8)),
                .bytes(2, Data("jane".utf8)),
            ])),
            .varint(2, 1),  // version, ignored
        ])
        let data = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: "=", with: "%3D")
        let accounts = try OTPAuthParser.parse("otpauth-migration://offline?data=\(data)")
        #expect(accounts == [
            OTPAccount(issuer: "ACME Co", name: "john@example.com", secret: Data("foobar".utf8), digits: 8, algorithm: .sha256),
            OTPAccount(issuer: "", name: "jane", secret: Data("plain".utf8)),
        ])
    }

    @Test("Rejects a migration link with only HOTP accounts")
    func migrationOnlyHOTP() {
        let payload = Protobuf.message([
            .bytes(1, Protobuf.message([.bytes(1, Data("x".utf8)), .varint(6, 1)])),
        ])
        #expect(throws: OTPAuthParser.ParseError.invalidMigrationData) {
            try OTPAuthParser.parse("otpauth-migration://offline?data=\(payload.base64EncodedString())")
        }
    }

    @Test("Rejects truncated migration data")
    func migrationTruncated() {
        // A length-delimited field claiming 100 bytes with only 1 present.
        let payload = Data([0x0A, 100, 0x01])
        #expect(throws: OTPAuthParser.ParseError.invalidMigrationData) {
            try OTPAuthParser.parse("otpauth-migration://offline?data=\(payload.base64EncodedString())")
        }
    }

    @Test("Rejects migration data with an oversized length", arguments: [
        // A length of 2^64 − 1, which doesn't fit in `Int`.
        Data([0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]),
        // A length of `Int.max`, which overflows when added to the read position.
        Data([0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0x00])
    ])
    func migrationOversizedLength(payload: Data) {
        #expect(throws: OTPAuthParser.ParseError.invalidMigrationData) {
            try OTPAuthParser.parse("otpauth-migration://offline?data=\(payload.base64EncodedString())")
        }
    }

    @Test("Parses one link per line and counts failures")
    func parseLines() {
        let text = """
        otpauth://totp/A:a?secret=MZXW6YTBOI

        otpauth://totp/B:b?secret=MZXW6YTBOI
        https://example.com
        otpauth://totp/x
        """
        let result = OTPAuthParser.parseLines(text)
        #expect(result.accounts.map(\.issuer) == ["A", "B"])
        #expect(result.failedLines == 2)
    }
}

/// A minimal protobuf encoder for building migration payloads.
private enum Protobuf {
    enum Field {
        case varint(Int, UInt64)
        case bytes(Int, Data)
    }

    static func message(_ fields: [Field]) -> Data {
        var data = Data()
        for field in fields {
            switch field {
            case .varint(let number, let value):
                data += varint(UInt64(number << 3 | 0))
                data += varint(value)
            case .bytes(let number, let bytes):
                data += varint(UInt64(number << 3 | 2))
                data += varint(UInt64(bytes.count))
                data += bytes
            }
        }
        return data
    }

    static func varint(_ value: UInt64) -> Data {
        var value = value
        var data = Data()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            data.append(byte)
        } while value != 0
        return data
    }
}
