import Foundation
@testable import MuninApp
import Testing

@Suite("PasswordCSVParser")
struct PasswordCSVParserTests {
    private func parse(_ csv: String) throws -> PasswordCSVParser.Import {
        try PasswordCSVParser.parse(Data(csv.utf8))
    }

    @Test("Parses a Chrome or Safari style export")
    func chrome() throws {
        let result = try parse("""
        name,url,username,password,note
        GitHub,https://github.com/login,octocat,hunter2,work
        """)
        let fields = try #require(result.passwords.first)
        #expect(result.passwords.count == 1)
        #expect(fields.name == "GitHub")
        #expect(fields.url == "https://github.com/login")
        #expect(fields.username == "octocat")
        #expect(fields.password == "hunter2")
        #expect(fields.note == "work")
        #expect(result.twoFactorAccounts.isEmpty)
    }

    @Test("Parses a Bitwarden export with a TOTP secret")
    func bitwarden() throws {
        let result = try parse("""
        folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
        ,,login,Example,a note,,0,https://example.com,me@example.com,secret,MZXW6YTBOI
        """)
        let fields = try #require(result.passwords.first)
        #expect(fields.name == "Example")
        #expect(fields.url == "https://example.com")
        #expect(fields.username == "me@example.com")
        #expect(fields.password == "secret")
        #expect(fields.note == "a note")
        #expect(result.twoFactorAccounts == [
            OTPAccount(issuer: "Example", name: "me@example.com", secret: Data("foobar".utf8)),
        ])
    }

    @Test("Parses a 1Password export with an otpauth URL")
    func onePassword() throws {
        let result = try parse("""
        Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes
        Site,https://site.test,user,pw,otpauth://totp/?secret=MZXW6YTBOI&digits=8,false,false,,
        """)
        #expect(result.passwords.count == 1)
        let account = try #require(result.twoFactorAccounts.first)
        // The URL has no label, so issuer and name come from the row.
        #expect(account.issuer == "Site")
        #expect(account.name == "user")
        #expect(account.digits == 8)
    }

    @Test("Handles quoted fields with commas, quotes and newlines")
    func quoting() throws {
        let result = try parse("name,url,username,password,note\r\n\"A, B\",https://a.test,\"say \"\"hi\"\"\",pw,\"line 1\nline 2\"\r\n")
        let fields = try #require(result.passwords.first)
        #expect(fields.name == "A, B")
        #expect(fields.username == "say \"hi\"")
        #expect(fields.note == "line 1\nline 2")
    }

    @Test("Strips a byte order mark and matches headers case-insensitively")
    func bomAndCase() throws {
        let result = try parse("\u{FEFF} NAME ,URL,Username,PASSWORD\nX,https://x.test,u,p")
        #expect(result.passwords.first?.name == "X")
    }

    @Test("Falls back to the host for a missing name")
    func nameFromURL() throws {
        let result = try parse("""
        name,url,username,password
        ,https://www.example.com/login,u,p
        ,example.org,u,p
        """)
        #expect(result.passwords.map(\.name) == ["example.com", "example.org"])
    }

    @Test("Skips blank rows and rows without credentials")
    func skipsEmptyRows() throws {
        let result = try parse("""
        name,url,username,password

        NoCreds,https://a.test,,
        ,,u,p
        Ok,,,p
        """)
        #expect(result.passwords.map(\.name) == ["Ok"])
    }

    @Test("Requires a password column and a name or URL column", arguments: [
        "name,url,username\nA,https://a.test,u",
        "username,password\nu,p",
    ])
    func missingColumns(_ csv: String) {
        #expect(throws: PasswordCSVParser.ParseError.self) { try parse(csv) }
    }

    @Test("Returns nothing for an empty file")
    func empty() throws {
        let result = try parse("")
        #expect(result.passwords.isEmpty)
        #expect(result.twoFactorAccounts.isEmpty)
    }

    @Test("Rejects data that isn't UTF-8")
    func unreadable() {
        #expect(throws: PasswordCSVParser.ParseError.self) {
            try PasswordCSVParser.parse(Data([0xFF, 0xFE, 0xFD]))
        }
    }

    @Test("Ignores an invalid TOTP value but keeps the password")
    func invalidTOTP() throws {
        let result = try parse("name,url,username,password,totp\nA,https://a.test,u,p,not-base32!")
        #expect(result.passwords.count == 1)
        #expect(result.twoFactorAccounts.isEmpty)
    }
}
