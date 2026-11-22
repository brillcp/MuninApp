import Foundation
import Networking

/// Endpoints of the iTunes Search API.
enum AppStoreEndpoint: EndpointType {
    /// `/lookup`: looks up an app by its bundle identifier.
    case lookup

    var path: String {
        switch self {
        case .lookup: return "lookup"
        }
    }
}

/// A request that looks up the app's latest version on the App Store.
///
/// On macOS, the lookup asks for the Mac App Store listing.
struct AppStoreLookupRequest: Requestable {
    /// The app's bundle identifier.
    let bundleID: String

    var httpMethod: HTTP.Method { .get }
    var encoding: Request.Encoding { .query }
    var authorization: Request.Authorization { .none }
    var parameters: HTTP.Parameters {
        #if os(macOS)
        ["bundleId": bundleID, "entity": "desktopSoftware"]
        #else
        ["bundleId": bundleID]
        #endif
    }
    var query: HTTP.Parameters { [:] }
    var body: (any Encodable & Sendable)? { nil }
    var endpoint: EndpointType { AppStoreEndpoint.lookup }
}

/// The response of ``AppStoreLookupRequest``.
nonisolated struct AppStoreLookup: Decodable, Sendable {
    /// An app found by the lookup.
    struct App: Decodable, Sendable {
        /// The version on the App Store, such as `1.2`.
        let version: String
        /// The app's App Store page.
        let trackViewUrl: URL
    }

    /// The apps found, at most one for a bundle identifier.
    let results: [App]
}
