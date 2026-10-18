import Foundation
import Networking

enum MuninRequest: Requestable {
    /// The signed-in user's encrypted entries.
    case entries
    /// Store one encrypted entry.
    case createEntry(CreateEntryBody)
    /// Delete one of the user's entries.
    case deleteEntry(UUID)
    /// The signed-in user's encrypted password items.
    case passwords
    /// Store a new password item; every field encrypted.
    case createPassword(PasswordFieldsBody)
    /// Replace an item's fields (an edit); bumps its last updated time.
    case updatePassword(UUID, PasswordFieldsBody)
    /// Bump an item's last updated time (the password was copied).
    case touchPassword(UUID)

    var httpMethod: HTTP.Method {
        switch self {
        case .entries, .passwords:                    return .get
        case .createEntry, .createPassword, .touchPassword: return .post
        case .deleteEntry:                            return .delete
        case .updatePassword:                         return .put
        }
    }

    var encoding: Request.Encoding {
        switch self {
        case .entries, .deleteEntry, .passwords, .touchPassword: return .query
        case .createEntry, .createPassword, .updatePassword:     return .json
        }
    }

    var authorization: Request.Authorization { .bearer }
    var parameters: HTTP.Parameters { [:] }

    var body: (any Encodable & Sendable)? {
        switch self {
        case .createEntry(let body):    return body
        case .createPassword(let body): return body
        case .updatePassword(_, let body): return body
        case .entries, .deleteEntry, .passwords, .touchPassword: return nil
        }
    }

    var endpoint: EndpointType {
        switch self {
        case .entries, .createEntry:     return MuninEndpoint.entries
        case .deleteEntry(let id):       return MuninEndpoint.entry(id)
        case .passwords, .createPassword: return MuninEndpoint.passwords
        case .touchPassword(let id):     return MuninEndpoint.passwordTouch(id)
        case .updatePassword(let id, _): return MuninEndpoint.password(id)
        }
    }
}

// MARK: - Bodies & response models

nonisolated struct CreateEntryBody: Encodable, Sendable {
    let ciphertext: String
}

/// Response from `GET /v1/entries`.
nonisolated struct EntriesResponse: Sendable, Decodable {
    let entries: [EncryptedEntry]
}

/// An entry as Munin stores it: an id and ciphertext only it can't read.
nonisolated struct EncryptedEntry: Sendable, Decodable {
    let id: UUID
    let ciphertext: String
}

// MARK: - Passwords

/// POST /v1/passwords. Every field is ciphertext.
nonisolated struct PasswordFieldsBody: Encodable, Sendable {
    let name: String
    let url: String
    let username: String
    let password: String
    let note: String
}

/// Response from `GET /v1/passwords`.
nonisolated struct PasswordsResponse: Sendable, Decodable {
    let passwords: [EncryptedPassword]
}

/// A password item as Munin stores it. Every field except `id` and
/// `updatedAt` is ciphertext.
nonisolated struct EncryptedPassword: Sendable, Decodable {
    let id: UUID
    let name: String
    let url: String
    let username: String
    let password: String
    let note: String
    let updatedAt: Date
}
