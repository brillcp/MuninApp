import Foundation
import Networking

/// Endpoints on the auth base URL (`/auth/v1`).
enum AuthEndpoint: EndpointType {
    /// `/token`, for both the identity token and the refresh token grants.
    case token

    var path: String {
        switch self {
        case .token: return "token"
        }
    }
}

/// Sign in with Apple: trades Apple's identity token for a session.
struct AppleIDTokenRequest: Requestable {
    /// Apple's identity token (a JWT).
    let idToken: String
    /// The raw nonce; Apple received its SHA-256.
    let nonce: String

    var httpMethod: HTTP.Method { .post }
    var encoding: Request.Encoding { .json }
    var authorization: Request.Authorization { .none }
    var parameters: HTTP.Parameters { [:] }
    var query: HTTP.Parameters { ["grant_type": "id_token"] }
    var body: (any Encodable & Sendable)? { IDTokenBody(provider: "apple", idToken: idToken, nonce: nonce) }
    var endpoint: EndpointType { AuthEndpoint.token }
}

/// Refresh-token exchange: trades a stored refresh token for a fresh session.
struct RefreshTokenRequest: Requestable {
    /// The refresh token from the current session.
    let refreshToken: String

    var httpMethod: HTTP.Method { .post }
    var encoding: Request.Encoding { .json }
    var authorization: Request.Authorization { .none }
    var parameters: HTTP.Parameters { [:] }
    var query: HTTP.Parameters { ["grant_type": "refresh_token"] }
    var body: (any Encodable & Sendable)? { RefreshBody(refreshToken: refreshToken) }
    var endpoint: EndpointType { AuthEndpoint.token }
}

// MARK: - Bodies

/// Body of `AppleIDTokenRequest`.
nonisolated private struct IDTokenBody: Encodable, Sendable {
    let provider: String
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider, nonce
        case idToken = "id_token"
    }
}

/// Body of `RefreshTokenRequest`.
nonisolated private struct RefreshBody: Encodable, Sendable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

// MARK: - Response

/// Response from `/auth/v1/token` for both grant types.
nonisolated struct AuthSession: Sendable, Decodable {
    /// The JWT sent to Munin as the bearer token.
    let accessToken: String
    /// Exchanged for a new session when the access token expires.
    let refreshToken: String
    /// The access token's lifetime in seconds.
    let expiresIn: Int
    /// The signed-in user.
    let user: User?

    /// The user in a session response.
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
