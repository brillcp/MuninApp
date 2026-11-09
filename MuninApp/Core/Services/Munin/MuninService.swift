import Foundation
import Networking

/// The live client for the Munin API.
///
/// Every call refreshes the access token first if needed. Calls that need the
/// master password proof send it in a header.
final class MuninService: MuninAPI {
    private let service: Network.Service
    private let tokenProvider: AuthTokenProvider

    /// Creates a service.
    ///
    /// - Parameter tokenProvider: The provider that supplies the bearer token.
    init(tokenProvider: AuthTokenProvider = .shared) {
        self.tokenProvider = tokenProvider
        service = MuninServiceFactory.makeService(tokenProvider: tokenProvider)
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

    /// Deletes a 2FA account.
    func deleteEntry(id: UUID, proof: String) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await authorizedService(proof: proof).response(MuninRequest.deleteEntry(id))
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

    /// Replaces a password item's fields.
    func updatePassword(id: UUID, _ body: PasswordFieldsBody, proof: String) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await authorizedService(proof: proof).request(MuninRequest.updatePassword(id, body))
    }

    /// Deletes a password item.
    func deletePassword(id: UUID, proof: String) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await authorizedService(proof: proof).response(MuninRequest.deletePassword(id))
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
    /// - Parameters:
    ///   - appleAuthorizationCode: An authorization code the server uses to
    ///     revoke the user's Sign in with Apple tokens, if available.
    ///   - proof: The master password proof, if a master password is set up.
    func deleteAccount(appleAuthorizationCode: String?, proof: String?) async throws {
        try await tokenProvider.ensureFresh()
        let body = DeleteAccountBody(appleAuthorizationCode: appleAuthorizationCode)
        _ = try await authorizedService(proof: proof).response(MuninRequest.deleteAccount(body))
    }
}

private extension MuninService {
    /// Returns a network service that sends the master password proof with each request.
    func authorizedService(proof: String?) -> Network.Service {
        guard let proof else { return service }
        return MuninServiceFactory.makeService(tokenProvider: tokenProvider, proof: proof)
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
