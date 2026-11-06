import Foundation
import Networking

/// A typed client for the Munin API.
///
/// Every call refreshes the access token first if needed.
final class MuninService {
    private let service: Network.Service
    private let tokenProvider: AuthTokenProvider

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - tokenProvider: The provider that supplies the bearer token.
    ///   - proof: The vault proof that the server requires for deletions and
    ///     password edits.
    init(tokenProvider: AuthTokenProvider, proof: String? = nil) {
        self.tokenProvider = tokenProvider
        service = MuninServiceFactory.makeService(tokenProvider: tokenProvider, proof: proof)
    }
}

extension MuninService {
    /// Fetches the user's encrypted 2FA accounts.
    func entries() async throws -> [EncryptedEntry] {
        try await tokenProvider.ensureFresh()
        let response: EntriesResponse = try await service.request(MuninRequest.entries)
        return response.entries
    }

    /// Stores an encrypted 2FA account.
    func createEntry(ciphertext: String) async throws -> EncryptedEntry {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.createEntry(CreateEntryBody(ciphertext: ciphertext)))
    }

    /// Deletes a 2FA account. Requires a proof.
    func deleteEntry(id: UUID) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.deleteEntry(id))
    }

    /// Fetches the user's encrypted password items.
    func passwords() async throws -> [EncryptedPassword] {
        try await tokenProvider.ensureFresh()
        let response: PasswordsResponse = try await service.request(MuninRequest.passwords)
        return response.passwords
    }

    /// Stores a new password item.
    func createPassword(_ body: PasswordFieldsBody) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.createPassword(body))
    }

    /// Replaces a password item's fields. Requires a proof.
    func updatePassword(id: UUID, _ body: PasswordFieldsBody) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.updatePassword(id, body))
    }

    /// Deletes a password item. Requires a proof.
    func deletePassword(id: UUID) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.deletePassword(id))
    }

    /// Updates a password item's modification date, such as after its password
    /// is copied.
    func touchPassword(id: UUID) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.touchPassword(id))
    }

    /// Fetches the wrapped vault key.
    ///
    /// - Returns: The key record, or `nil` if the user hasn't set up a master password.
    func vaultKey() async throws -> VaultKeyRecord? {
        try await tokenProvider.ensureFresh()
        do {
            return try await service.request(MuninRequest.vaultKey)
        } catch Network.Service.NetworkError.badServerResponse(.notFound, _) {
            return nil
        }
    }

    /// Saves the user's first vault key.
    ///
    /// - Returns: `false` if a master password already exists, such as one set
    ///   up on another device.
    func createVaultKey(_ body: VaultKeyRequestBody) async throws -> Bool {
        try await tokenProvider.ensureFresh()
        do {
            _ = try await service.response(MuninRequest.createVaultKey(body))
            return true
        } catch Network.Service.NetworkError.badServerResponse(.conflict, _) {
            return false
        }
    }

    /// Replaces the vault key after a master password change or reset.
    ///
    /// - Parameter body: The new key, with `currentProof` set.
    func replaceVaultKey(_ body: VaultKeyRequestBody) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.replaceVaultKey(body))
    }

    /// Fetches whether a subscription is required and whether the user has one.
    func subscription() async throws -> SubscriptionStatus {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.subscription)
    }

    /// Links an App Store purchase to the user.
    ///
    /// The server verifies the transaction with Apple.
    ///
    /// - Returns: The resulting subscription status.
    func linkSubscription(transactionID: String) async throws -> SubscriptionStatus {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.linkSubscription(LinkSubscriptionBody(transactionId: transactionID)))
    }

    /// Deletes the account, including the vault key, passwords, 2FA accounts,
    /// and subscription link.
    ///
    /// Requires a proof once a master password is set up.
    ///
    /// - Parameter appleAuthorizationCode: An authorization code the server
    ///   uses to revoke the user's Sign in with Apple tokens, if available.
    func deleteAccount(appleAuthorizationCode: String?) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.deleteAccount(DeleteAccountBody(appleAuthorizationCode: appleAuthorizationCode)))
    }
}

// MARK: - Errors

/// The API's error body, `{"error": "code"}`.
nonisolated private struct MuninErrorBody: Decodable {
    /// The error code, such as `subscription_account_mismatch`.
    let error: String
}

extension Error {
    /// A short, user-facing description of an API request failure.
    var muninDescription: String {
        if let networkError = self as? Network.Service.NetworkError {
            switch networkError {
            case .badServerResponse(let status, let data):
                switch (try? JSONDecoder().decode(MuninErrorBody.self, from: data))?.error {
                case "subscription_account_mismatch": return Localized("errors.munin.subscriptionOtherAccount")
                case "subscription_linked_elsewhere": return Localized("errors.munin.subscriptionLinkedElsewhere")
                case "transaction_not_found": return Localized("errors.munin.transactionNotFound")
                case "app_store_unavailable", "subscriptions_unavailable": return Localized("errors.munin.appStoreUnavailable")
                default: break
                }
                switch status {
                case .notFound: return Localized("errors.munin.notFound", APIConfig.apiBaseURL.absoluteString)
                case .unprocessableEntity: return Localized("errors.munin.vaultFull")
                case .forbidden: return Localized("errors.munin.proof")
                case .tooManyRequests: return Localized("errors.munin.tooManyAttempts")
                case .paymentRequired: return Localized("errors.munin.subscriptionRequired")
                default: return Localized("errors.munin.http", status.rawValue)
                }
            case .decodingError:
                return Localized("errors.munin.unexpectedResponse", APIConfig.apiBaseURL.absoluteString)
            case .networkError(let underlying):
                return Localized("errors.munin.unreachable", underlying.localizedDescription)
            case .encodingError:
                return Localized("errors.munin.badRequest")
            }
        }
        return localizedDescription
    }
}
