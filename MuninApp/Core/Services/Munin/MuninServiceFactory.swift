import Foundation
import Networking

/// A factory that creates network services for the app's API.
enum MuninServiceFactory {
    /// The header that carries the master password proof for edits, deletions, and master password changes.
    static let proofHeader = "X-Munin-Proof"

    /// Creates a service for the app's API.
    ///
    /// - Parameters:
    ///   - tokenProvider: The provider that authenticates each request.
    ///   - proof: The master password proof to send in ``proofHeader`` on every request, if any.
    ///   - interceptors: Interceptors applied to each request.
    /// - Returns: A configured network service.
    static func makeService(
        tokenProvider: AuthTokenProvider,
        proof: String? = nil,
        interceptors: [any NetworkInterceptor] = []
    ) -> Network.Service {
        let server = ServerConfig(
            baseURL: APIConfig.apiBaseURL,
            additionalHeaders: proof.map { [proofHeader: $0] } ?? [:],
            tokenProvider: tokenProvider
        )
        return Network.Service(
            server: server,
            interceptors: interceptors,
            logger: nil
        )
    }
}
