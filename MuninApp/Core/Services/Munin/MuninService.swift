import Foundation
import Networking

/// Typed access to Munin's API. Every call refreshes the Supabase JWT first if needed.
final class MuninService {
    /// The configured network service.
    private let service: Network.Service
    /// Supplies and refreshes the bearer token.
    private let tokenProvider: SupabaseTokenProvider

    /// Pass `proof` for deletes and password edits; Munin rejects them without it.
    init(tokenProvider: SupabaseTokenProvider, proof: String? = nil) {
        self.tokenProvider = tokenProvider
        service = MuninServiceFactory.makeService(tokenProvider: tokenProvider, proof: proof)
    }
}

extension MuninService {
    /// The user's encrypted 2FA accounts.
    func entries() async throws -> [EncryptedEntry] {
        try await tokenProvider.ensureFresh()
        let response: EntriesResponse = try await service.request(MuninRequest.entries)
        return response.entries
    }

    /// Stores one encrypted 2FA account.
    func createEntry(ciphertext: String) async throws -> EncryptedEntry {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.createEntry(CreateEntryBody(ciphertext: ciphertext)))
    }

    /// Deletes one 2FA account. Needs a proof.
    func deleteEntry(id: UUID) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.deleteEntry(id))
    }

    /// The user's encrypted password items.
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

    /// Replaces a password item's fields. Needs a proof.
    func updatePassword(id: UUID, _ body: PasswordFieldsBody) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.updatePassword(id, body))
    }

    /// Deletes a password item. Needs a proof.
    func deletePassword(id: UUID) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.deletePassword(id))
    }

    /// Bumps a password item's last updated time (its password was copied).
    func touchPassword(id: UUID) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.touchPassword(id))
    }

    /// The wrapped vault key, or nil if the user hasn't set up a master password yet.
    func vaultKey() async throws -> VaultKeyRecord? {
        try await tokenProvider.ensureFresh()
        do {
            return try await service.request(MuninRequest.vaultKey)
        } catch Network.Service.NetworkError.badServerResponse(.notFound, _) {
            return nil
        }
    }

    /// Saves the first vault key. Returns false if a master password was
    /// already set up (from another device).
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
    /// `body.currentProof` must be set.
    func replaceVaultKey(_ body: VaultKeyRequestBody) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.replaceVaultKey(body))
    }

    /// Whether a subscription is required, and whether the user has one.
    func subscription() async throws -> SubscriptionStatus {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.subscription)
    }

    /// Links an App Store purchase to the user. Munin checks it with Apple and
    /// returns the resulting status.
    func linkSubscription(transactionID: String) async throws -> SubscriptionStatus {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.linkSubscription(LinkSubscriptionBody(transactionId: transactionID)))
    }
}

// MARK: - Errors

extension Error {
    /// A short, user-facing explanation of a Munin request failure.
    var muninDescription: String {
        if let networkError = self as? Network.Service.NetworkError {
            switch networkError {
            case .badServerResponse(let status, _):
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
