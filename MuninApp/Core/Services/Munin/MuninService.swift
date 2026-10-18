import Foundation
import Networking

final class MuninService {
    private let service: Network.Service
    private let tokenProvider: SupabaseTokenProvider

    init(tokenProvider: SupabaseTokenProvider) {
        self.tokenProvider = tokenProvider
        service = MuninServiceFactory.makeService(tokenProvider: tokenProvider)
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

    func touchPassword(id: UUID) async throws -> EncryptedPassword {
        try await tokenProvider.ensureFresh()
        return try await service.request(MuninRequest.touchPassword(id))
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
