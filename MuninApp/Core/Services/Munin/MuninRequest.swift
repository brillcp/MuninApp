import Foundation
import Networking

/// Every request the app makes to Munin.
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
    /// Delete one of the user's password items.
    case deletePassword(UUID)
    /// The user's wrapped vault key and KDF settings.
    case vaultKey
    /// First master password setup.
    case createVaultKey(VaultKeyRequestBody)
    /// New master password; needs `currentProof`.
    case replaceVaultKey(VaultKeyRequestBody)
    /// Whether a subscription is required, and whether the user has one.
    case subscription
    /// Links an App Store purchase to the user; Munin checks it with Apple.
    case linkSubscription(LinkSubscriptionBody)
    /// Deletes the account and everything in it; needs a proof once a master password is set up.
    case deleteAccount

    var httpMethod: HTTP.Method {
        switch self {
        case .entries, .passwords, .vaultKey, .subscription: return .get
        case .createEntry, .createPassword, .touchPassword, .createVaultKey, .linkSubscription: return .post
        case .deleteEntry, .deletePassword, .deleteAccount: return .delete
        case .updatePassword, .replaceVaultKey:       return .put
        }
    }

    var encoding: Request.Encoding {
        switch self {
        case .entries, .deleteEntry, .passwords, .touchPassword, .deletePassword, .vaultKey, .subscription, .deleteAccount: return .query
        case .createEntry, .createPassword, .updatePassword, .createVaultKey, .replaceVaultKey, .linkSubscription: return .json
        }
    }

    var authorization: Request.Authorization { .bearer }
    var parameters: HTTP.Parameters { [:] }

    var body: (any Encodable & Sendable)? {
        switch self {
        case .createEntry(let body):    return body
        case .createPassword(let body): return body
        case .updatePassword(_, let body): return body
        case .createVaultKey(let body), .replaceVaultKey(let body): return body
        case .linkSubscription(let body): return body
        case .entries, .deleteEntry, .passwords, .touchPassword, .deletePassword, .vaultKey, .subscription, .deleteAccount: return nil
        }
    }

    var endpoint: EndpointType {
        switch self {
        case .entries, .createEntry:     return MuninEndpoint.entries
        case .deleteEntry(let id):       return MuninEndpoint.entry(id)
        case .passwords, .createPassword: return MuninEndpoint.passwords
        case .touchPassword(let id):     return MuninEndpoint.passwordTouch(id)
        case .updatePassword(let id, _): return MuninEndpoint.password(id)
        case .deletePassword(let id):    return MuninEndpoint.password(id)
        case .vaultKey, .createVaultKey, .replaceVaultKey: return MuninEndpoint.vaultKey
        case .subscription, .linkSubscription: return MuninEndpoint.subscription
        case .deleteAccount:             return MuninEndpoint.account
        }
    }
}

// MARK: - Bodies & response models

/// `POST /v1/entries`: one encrypted 2FA account.
nonisolated struct CreateEntryBody: Encodable, Sendable {
    /// The account, encrypted with the vault key.
    let ciphertext: String
}

/// Response from `GET /v1/entries`.
nonisolated struct EntriesResponse: Sendable, Decodable {
    let entries: [EncryptedEntry]
}

/// An entry as Munin stores it: an id, and ciphertext Munin can't read.
nonisolated struct EncryptedEntry: Sendable, Decodable {
    let id: UUID
    let ciphertext: String
}

// MARK: - Passwords

/// `POST /v1/passwords` and `PUT /v1/passwords/{id}`. Every field is ciphertext.
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

// MARK: - Vault key

/// Response from `GET /v1/vault-key`. The wrapped keys are AES-GCM ciphertext;
/// `kdf` is `KDFParameters` as JSON.
nonisolated struct VaultKeyRecord: Sendable, Decodable {
    let passwordWrappedKey: String
    let recoveryWrappedKey: String
    let kdf: String
}

/// `POST` and `PUT /v1/vault-key`.
nonisolated struct VaultKeyRequestBody: Encodable, Sendable {
    /// The vault key wrapped with the master password's key.
    let passwordWrappedKey: String
    /// The vault key wrapped with the recovery key's key.
    let recoveryWrappedKey: String
    /// `KDFParameters` as JSON.
    let kdf: String
    /// Proof of the new master password; Munin stores a hash of it.
    let passwordProof: String
    /// Proof of the recovery key; Munin stores a hash of it.
    let recoveryProof: String
    /// PUT only: proof from the current master password or the recovery key.
    let currentProof: String?
}

// MARK: - Subscription

/// `GET` and `POST /v1/subscription` response.
nonisolated struct SubscriptionStatus: Sendable, Decodable, Equatable {
    /// Whether changes need an active subscription.
    let required: Bool
    /// Whether the user has an active subscription or free trial.
    let active: Bool
    /// When the current period ends, if there's a subscription.
    let expiresAt: Date?
}

/// `POST /v1/subscription`: a StoreKit transaction ID for Munin to look up with Apple.
nonisolated struct LinkSubscriptionBody: Encodable, Sendable {
    let transactionId: String
}
