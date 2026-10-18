import Foundation
import Networking

/// Endpoints on the Supabase Auth base URL (`/auth/v1`).
enum SupabaseAuthEndpoint: EndpointType {
    case token

    var path: String {
        switch self {
        case .token: return "token"
        }
    }
}

/// Sign in with Apple: trades Apple's identity token for a Supabase session.
/// `nonce` is the raw nonce; Apple received its SHA-256.
struct AppleIDTokenRequest: Requestable {
    let idToken: String
    let nonce: String

    var httpMethod: HTTP.Method { .post }
    var encoding: Request.Encoding { .json }
    var authorization: Request.Authorization { .none }
    var parameters: HTTP.Parameters { [:] }
    var query: HTTP.Parameters { ["grant_type": "id_token"] }
    var body: (any Encodable & Sendable)? { IDTokenBody(provider: "apple", idToken: idToken, nonce: nonce) }
    var endpoint: EndpointType { SupabaseAuthEndpoint.token }
}

/// Refresh-token exchange: trades a stored refresh token for a fresh session.
struct RefreshTokenRequest: Requestable {
    let refreshToken: String

    var httpMethod: HTTP.Method { .post }
    var encoding: Request.Encoding { .json }
    var authorization: Request.Authorization { .none }
    var parameters: HTTP.Parameters { [:] }
    var query: HTTP.Parameters { ["grant_type": "refresh_token"] }
    var body: (any Encodable & Sendable)? { RefreshBody(refreshToken: refreshToken) }
    var endpoint: EndpointType { SupabaseAuthEndpoint.token }
}

// MARK: - Bodies

nonisolated private struct IDTokenBody: Encodable, Sendable {
    let provider: String
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider, nonce
        case idToken = "id_token"
    }
}

nonisolated private struct RefreshBody: Encodable, Sendable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

// MARK: - Response

/// Response from `/auth/v1/token` for both grant types.
nonisolated struct SupabaseSession: Sendable, Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User?

    struct User: Sendable, Decodable {
        let id: String
        let email: String?
    }

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
