import Foundation
import Networking

/// Builds the network service used to talk to Munin.
enum MuninServiceFactory {
    /// Header Munin checks on deletes, edits and master password changes.
    static let proofHeader = "X-Munin-Proof"

    /// A service for Munin's API that authenticates with `tokenProvider` and,
    /// when given, sends `proof` in the proof header on every request.
    static func makeService(
        tokenProvider: SupabaseTokenProvider,
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
