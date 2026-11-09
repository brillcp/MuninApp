import Foundation
import Networking

/// The requests the app sends to the Munin server.
enum MuninRequest: Requestable {
    /// Fetches the signed-in user's encrypted 2FA entries.
    case entries
    /// Creates an encrypted 2FA entry.
    case createEntry(CreateEntryBody)
    /// Deletes a 2FA entry.
    case deleteEntry(UUID)
    /// Fetches the signed-in user's encrypted password items.
    case passwords
    /// Creates a password item with every field encrypted.
    case createPassword(PasswordFieldsBody)
    /// Replaces a password item's fields and updates its modification date.
    case updatePassword(UUID, PasswordFieldsBody)
    /// Updates a password item's modification date, for example after its
    /// password is copied.
    case touchPassword(UUID)
    /// Deletes a password item.
    case deletePassword(UUID)
    /// Fetches the user's wrapped vault key and key derivation settings.
    case vaultKey
    /// Stores the wrapped vault key when the user first sets a master password.
    case createVaultKey(VaultKeyRequestBody)
    /// Replaces the wrapped vault key after a master password change.
    ///
    /// Requires `currentProof`.
    case replaceVaultKey(VaultKeyRequestBody)
    /// Fetches whether a subscription is required and whether the user has one.
    case subscription
    /// Links an App Store purchase to the user. The server verifies it with Apple.
    case linkSubscription(LinkSubscriptionBody)
    /// Deletes the account and all its data, and revokes Sign in with Apple.
    ///
    /// Requires a proof once a master password is set.
    case deleteAccount(DeleteAccountBody)

    /// The HTTP method for the request.
    var httpMethod: HTTP.Method {
        switch self {
        case .entries, .passwords, .vaultKey, .subscription: return .get
        case .createEntry, .createPassword, .touchPassword, .createVaultKey, .linkSubscription: return .post
        case .deleteEntry, .deletePassword, .deleteAccount: return .delete
        case .updatePassword, .replaceVaultKey:       return .put
        }
    }

    /// How the request's parameters and body are encoded.
    var encoding: Request.Encoding {
        switch self {
        case .entries, .deleteEntry, .passwords, .touchPassword, .deletePassword, .vaultKey, .subscription: return .query
        case .createEntry, .createPassword, .updatePassword, .createVaultKey, .replaceVaultKey, .linkSubscription, .deleteAccount: return .json
        }
    }

    /// The authorization scheme. Every request carries the user's bearer token.
    var authorization: Request.Authorization { .bearer }
    /// The query parameters. No request uses any.
    var parameters: HTTP.Parameters { [:] }

    /// The JSON body, or `nil` for requests without one.
    var body: (any Encodable & Sendable)? {
        switch self {
        case .createEntry(let body):    return body
        case .createPassword(let body): return body
        case .updatePassword(_, let body): return body
        case .createVaultKey(let body), .replaceVaultKey(let body): return body
        case .linkSubscription(let body): return body
        case .deleteAccount(let body): return body
        case .entries, .deleteEntry, .passwords, .touchPassword, .deletePassword, .vaultKey, .subscription: return nil
        }
    }

    /// The server path for the request.
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

// MARK: - Entries

/// The body of `POST /v1/entries`.
nonisolated struct CreateEntryBody: Encodable, Sendable {
    /// The account, encrypted with the vault key.
    let ciphertext: String
}

/// The response from `GET /v1/entries`.
nonisolated struct EntriesResponse: Sendable, Decodable {
    /// The user's encrypted 2FA entries.
    let entries: [EncryptedEntry]
}

/// A 2FA entry as the server stores it: an identifier and ciphertext the
/// server can't read.
nonisolated struct EncryptedEntry: Sendable, Decodable {
    /// The entry's server identifier.
    let id: UUID
    /// The account, encrypted with the vault key.
    let ciphertext: String
}

// MARK: - Passwords

/// The body of `POST /v1/passwords` and `PUT /v1/passwords/{id}`.
///
/// Every field is ciphertext.
nonisolated struct PasswordFieldsBody: Encodable, Sendable {
    /// The encrypted name.
    let name: String
    /// The encrypted website.
    let url: String
    /// The encrypted username.
    let username: String
    /// The encrypted password.
    let password: String
    /// The encrypted note.
    let note: String
}

/// The response from `GET /v1/passwords`.
nonisolated struct PasswordsResponse: Sendable, Decodable {
    /// The user's encrypted password items.
    let passwords: [EncryptedPassword]
}

/// A password item as the server stores it.
///
/// Every field except `id` and `updatedAt` is ciphertext.
nonisolated struct EncryptedPassword: Sendable, Decodable {
    /// The item's server identifier.
    let id: UUID
    /// The encrypted name.
    let name: String
    /// The encrypted website.
    let url: String
    /// The encrypted username.
    let username: String
    /// The encrypted password.
    let password: String
    /// The encrypted note.
    let note: String
    /// The date the item was last modified.
    let updatedAt: Date
}

// MARK: - Vault key

/// The response from `GET /v1/vault-key`.
///
/// The wrapped keys are AES-GCM ciphertext, and `kdf` is JSON-encoded
/// ``KDFParameters``.
nonisolated struct VaultKeyRecord: Sendable, Decodable {
    /// The vault key wrapped with the key derived from the master password.
    let passwordWrappedKey: String
    /// The vault key wrapped with the key derived from the recovery key.
    let recoveryWrappedKey: String
    /// JSON-encoded ``KDFParameters``.
    let kdf: String
}

/// The body of `POST` and `PUT /v1/vault-key`.
nonisolated struct VaultKeyRequestBody: Encodable, Sendable {
    /// The vault key wrapped with the key derived from the master password.
    let passwordWrappedKey: String
    /// The vault key wrapped with the key derived from the recovery key.
    let recoveryWrappedKey: String
    /// JSON-encoded ``KDFParameters``.
    let kdf: String
    /// A proof of the new master password. The server stores its hash.
    let passwordProof: String
    /// A proof of the recovery key. The server stores its hash.
    let recoveryProof: String
    /// A proof from the current master password or the recovery key.
    ///
    /// Required for `PUT` only.
    let currentProof: String?
}

// MARK: - Subscription

/// The response from `GET` and `POST /v1/subscription`.
nonisolated struct SubscriptionStatus: Sendable, Decodable, Equatable {
    /// A Boolean value that indicates whether changes require an active subscription.
    let required: Bool
    /// A Boolean value that indicates whether the user has an active subscription
    /// or free trial.
    let active: Bool
    /// A Boolean value that indicates whether Apple couldn't charge the renewal and
    /// is retrying, or `nil` if the server doesn't report it.
    let billingIssue: Bool?
}

/// The body of `POST /v1/subscription`: a StoreKit transaction identifier the
/// server verifies with Apple.
nonisolated struct LinkSubscriptionBody: Encodable, Sendable {
    /// The StoreKit transaction identifier.
    let transactionId: String
}

/// The body of `DELETE /v1/account`.
///
/// Carries the authorization code from reauthenticating with Sign in with
/// Apple, which the server uses to revoke the user's Apple tokens.
nonisolated struct DeleteAccountBody: Encodable, Sendable {
    /// The authorization code from Sign in with Apple, or `nil` if none is available.
    let appleAuthorizationCode: String?
}
