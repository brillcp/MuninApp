import Foundation
import Networking

/// Endpoints relative to the authentication base URL (`/auth/v1`).
enum AuthEndpoint: EndpointType {
    /// The token endpoint, used for both identity token and refresh token grants.
    case token

    var path: String {
        switch self {
        case .token: return "token"
        }
    }
}

/// A request that exchanges a Sign in with Apple identity token for a session.
struct AppleIDTokenRequest: Requestable {
    /// The identity token from Apple, as a JWT.
    let idToken: String
    /// The raw nonce whose SHA-256 hash was sent to Apple.
    let nonce: String

    var httpMethod: HTTP.Method { .post }
    var encoding: Request.Encoding { .json }
    var authorization: Request.Authorization { .none }
    var parameters: HTTP.Parameters { [:] }
    var query: HTTP.Parameters { ["grant_type": "id_token"] }
    var body: (any Encodable & Sendable)? { IDTokenBody(provider: "apple", idToken: idToken, nonce: nonce) }
    var endpoint: EndpointType { AuthEndpoint.token }
}

/// A request that exchanges a refresh token for a new session.
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

/// The request body of ``AppleIDTokenRequest``.
nonisolated private struct IDTokenBody: Encodable, Sendable {
    let provider: String
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider, nonce
        case idToken = "id_token"
    }
}

/// The request body of ``RefreshTokenRequest``.
nonisolated private struct RefreshBody: Encodable, Sendable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

// MARK: - Response

/// A session returned by the token endpoint for either grant type.
nonisolated struct AuthSession: Sendable, Decodable {
    /// The JWT sent to the server as the bearer token.
    let accessToken: String
    /// The token exchanged for a new session when the access token expires.
    let refreshToken: String
    /// The access token's lifetime in seconds.
    let expiresIn: Int
    /// The signed-in user.
    let user: User?

    /// The user described in a session response.
    struct User: Sendable, Decodable {
        /// The user's unique identifier.
        let id: String
        /// The user's email address, if shared.
        let email: String?
    }

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
