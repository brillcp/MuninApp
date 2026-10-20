import Foundation

/// Reads a password export CSV (NordPass and similar) into `PasswordFields`.
///
/// Columns are matched by the header line, case-insensitive: `name`, `url`,
/// `username`, `password`, `note`; others are ignored. Handles quoted fields
/// with commas, quotes ("") and line breaks. Runs in memory only.
enum PasswordCSVParser {
    /// Why a file couldn't be imported.
    enum ParseError: LocalizedError {
        /// The file isn't UTF-8 text.
        case unreadable
        /// The header has no `name` or no `password` column.
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
    /// Skips blank rows and rows with neither a name nor a URL, or with
    /// neither a username nor a password.
    static func parse(_ data: Data) throws -> [PasswordFields] {
        guard var text = String(data: data, encoding: .utf8) else { throw ParseError.unreadable }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        let rows = records(in: text)
        guard let header = rows.first else { return [] }
        let columns = Dictionary(
            header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces).lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard columns["name"] != nil, columns["password"] != nil else { throw ParseError.missingColumns }

        /// The row's value in `column`, or an empty string if the column or value is missing.
        func value(_ column: String, in row: [String]) -> String {
            guard let index = columns[column], index < row.count else { return "" }
            return row[index]
        }

        return rows.dropFirst().compactMap { row in
            let fields = PasswordFields(
                name: value("name", in: row),
                url: value("url", in: row),
                username: value("username", in: row),
                password: value("password", in: row),
                note: value("note", in: row)
            )
            // Skip blank lines and rows with nothing to log in with.
            guard !fields.name.isEmpty || !fields.url.isEmpty,
                  !fields.password.isEmpty || !fields.username.isEmpty else { return nil }
            return fields
        }
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
