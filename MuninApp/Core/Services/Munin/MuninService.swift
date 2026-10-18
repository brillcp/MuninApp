import Foundation
import Networking

final class MuninService {
    private let service: Network.Service
    private let tokenProvider: SupabaseTokenProvider

    /// Pass `proof` for deletes and password edits; Munin rejects them without it.
    init(tokenProvider: SupabaseTokenProvider, proof: String? = nil) {
        self.tokenProvider = tokenProvider
        service = MuninServiceFactory.makeService(tokenProvider: tokenProvider, proof: proof)
    }
}

extension MuninService {
    func entries() async throws -> [EncryptedEntry] {
        try await tokenProvider.ensureFresh()
        let response: EntriesResponse = try await service.request(MuninRequest.entries)
        return response.entries
    }

    func createEntry(ciphertext: String) async throws -> EncryptedEntry {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.createEntry(CreateEntryBody(ciphertext: ciphertext)))
    }

    func deleteEntry(id: UUID) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.deleteEntry(id))
    }

    func passwords() async throws -> [EncryptedPassword] {
        try await tokenProvider.ensureFresh()
        let response: PasswordsResponse = try await service.request(MuninRequest.passwords)
        return response.passwords
    }

    func createPassword(_ body: PasswordFieldsBody) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.createPassword(body))
    }

    func updatePassword(id: UUID, _ body: PasswordFieldsBody) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.updatePassword(id, body))
    }

    func deletePassword(id: UUID) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.deletePassword(id))
    }

    func touchPassword(id: UUID) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.touchPassword(id))
    }

    /// Nil if the user hasn't set up a master password yet.
    func vaultKey() async throws -> VaultKeyRecord? {
        try await tokenProvider.ensureFresh()
        do {
            return try await service.request(MuninRequest.vaultKey)
        } catch Network.Service.NetworkError.badServerResponse(.notFound, _) {
            return nil
        }
    }

    /// False if a master password was already set up (from another device).
    func createVaultKey(_ body: VaultKeyRequestBody) async throws -> Bool {
        try await tokenProvider.ensureFresh()
        do {
            _ = try await service.response(MuninRequest.createVaultKey(body))
            return true
        } catch Network.Service.NetworkError.badServerResponse(.conflict, _) {
            return false
        }
    }

    func replaceVaultKey(_ body: VaultKeyRequestBody) async throws {
        try await tokenProvider.ensureFresh()
        _ = try await service.response(MuninRequest.replaceVaultKey(body))
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
                default:        return Localized("errors.munin.http", status.rawValue)
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
