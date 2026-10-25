import Foundation

/// Reads a password export CSV into `PasswordFields`: Munin's own export,
/// NordPass, Chrome, Apple Passwords, 1Password, Bitwarden, LastPass, Proton
/// Pass, Firefox and similar.
///
/// Columns are matched by the header line, case-insensitive, under the names
/// those apps use (see `Field.headerNames`); others are ignored. Handles quoted
/// fields with commas, quotes ("") and line breaks. Runs in memory only.
enum PasswordCSVParser {
    /// A field Munin imports, and the header names other apps use for it.
    private enum Field: CaseIterable {
        case name, url, username, password, note

        /// Lowercased header names for the field, in order of preference. A
        /// row's value comes from the first of these columns that isn't empty.
        var headerNames: [String] {
            switch self {
            case .name:     ["name", "title"]
            case .url:      ["url", "login_uri", "website", "uri"]
            case .username: ["username", "login_username", "email"]
            case .password: ["password", "login_password"]
            case .note:     ["note", "notes", "extra", "comments"]
            }
        }
    }

    /// Why a file couldn't be imported.
    enum ParseError: LocalizedError {
        /// The file isn't UTF-8 text.
        case unreadable
        /// The header has no password column, or neither a name nor a website column.
        case missingColumns

        var errorDescription: String? {
            switch self {
            case .unreadable:     Localized("import.error.unreadable")
            case .missingColumns: Localized("import.error.columns")
            }
        }
    }

    /// Parses a CSV export into password fields.
    ///
    /// A row without a name (Firefox has no name column) is named after its
    /// website's domain. Skips blank rows and rows with neither a name nor a
    /// URL, or with neither a username nor a password (such as Bitwarden's
    /// secure notes and cards).
    static func parse(_ data: Data) throws -> [PasswordFields] {
        guard var text = String(data: data, encoding: .utf8) else { throw ParseError.unreadable }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        let rows = records(in: text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else { return [] }
        let columns = Dictionary(uniqueKeysWithValues: Field.allCases.map { field in
            (field, field.headerNames.compactMap { header.firstIndex(of: $0) })
        })
        guard columns[.password]?.isEmpty == false,
              columns[.name]?.isEmpty == false || columns[.url]?.isEmpty == false else {
            throw ParseError.missingColumns
        }

        /// The row's first non-empty value among `field`'s columns, or an empty string.
        func value(_ field: Field, in row: [String]) -> String {
            for index in columns[field] ?? [] where index < row.count && !row[index].isEmpty {
                return row[index]
            }
            return ""
        }

        return rows.dropFirst().compactMap { row in
            let url = value(.url, in: row)
            let name = value(.name, in: row)
            let fields = PasswordFields(
                name: name.isEmpty ? siteName(from: url) : name,
                url: url,
                username: value(.username, in: row),
                password: value(.password, in: row),
                note: value(.note, in: row)
            )
            // Skip blank lines and rows with nothing to log in with.
            guard !fields.name.isEmpty || !fields.url.isEmpty,
                  !fields.password.isEmpty || !fields.username.isEmpty else { return nil }
            return fields
        }
    }

    /// The website's domain without "www.", to name a row that has no name.
    /// The URL itself if it has no host; empty if there's no URL.
    private static func siteName(from url: String) -> String {
        guard !url.isEmpty else { return "" }
        let host = URL(string: url)?.host ?? URL(string: "https://\(url)")?.host ?? url
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// RFC 4180 records: commas between fields, quotes around fields that need them.
    private static func records(in text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var characters = text.makeIterator()
        var pending: Character?

        while let character = pending ?? characters.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    let next = characters.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        pending = next
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                inQuotes = true
            case ",":
                record.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                record.append(field)
                records.append(record)
                record = []
                field = ""
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
