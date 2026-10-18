import Foundation
import Networking

enum MuninServiceFactory {
    /// Header Munin checks on deletes, edits and master password changes.
    static let proofHeader = "X-Munin-Proof"

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
