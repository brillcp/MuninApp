import Foundation
import Networking

enum MuninServiceFactory {
    static func makeService(
        tokenProvider: SupabaseTokenProvider,
        interceptors: [any NetworkInterceptor] = []
    ) -> Network.Service {
        let server = ServerConfig(
            baseURL: APIConfig.apiBaseURL,
            tokenProvider: tokenProvider
        )
        return Network.Service(
            server: server,
            interceptors: interceptors,
            logger: nil
        )
    }
}
