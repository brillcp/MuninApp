import Foundation
import Networking

/// Holds the session from Sign in with Apple and supplies its JWT as
/// the bearer token for Munin.
///
/// JWTs are short-lived (about an hour). Callers `await ensureFresh()` before
/// a request; a missing, expired or nearly expired JWT is exchanged for a new
/// pair using the stored refresh token. Tokens persist in the Keychain.
final class AuthTokenProvider: TokenProvidable {
    /// The app-wide instance.
    static let shared = AuthTokenProvider()

    /// The current access token (JWT).
    private var cachedToken: String?
    /// The current refresh token.
    private var cachedRefreshToken: String?
    /// When the access token expires.
    private var cachedExpiresAt: Date?

    /// Refresh slightly before actual expiry so an in-flight request doesn't
    /// race the boundary.
    private let refreshLeeway: TimeInterval = 30

    /// In-flight refresh shared by concurrent callers. The auth server rotates the
    /// refresh token on every exchange, so two parallel refreshes would race.
    private var inflightRefresh: Task<Void, Error>?

    /// Talks to the auth server.
    private let authService: Network.Service

    /// Restores the session saved by the previous launch.
    init() {
        cachedToken = KeychainService.loadAccessToken()
        cachedRefreshToken = KeychainService.loadRefreshToken()
        cachedExpiresAt = cachedToken.flatMap(Self.expiry(of:))

        let server = ServerConfig(
            baseURL: APIConfig.authBaseURL,
            additionalHeaders: ["apikey": APIConfig.anonKey],
            tokenProvider: nil
        )
        authService = Network.Service(server: server, logger: nil)
    }
}

extension AuthTokenProvider {
    /// The current access token, or `.missing` when signed out.
    var token: Result<String, TokenProvidableError> {
        guard let cachedToken else { return .failure(.missing) }
        return .success(cachedToken)
    }

    /// Replaces the cached access token (`TokenProvidable` requirement).
    func setToken(_ token: String) {
        cachedToken = token
    }

    /// Forgets the session: clears the cached tokens and deletes them from the Keychain.
    func reset() {
        cachedToken = nil
        cachedRefreshToken = nil
        cachedExpiresAt = nil
        KeychainService.deleteAccessToken()
        KeychainService.deleteRefreshToken()
    }

    /// Whether a refresh token is stored, so a session can be resumed.
    var hasSession: Bool { cachedRefreshToken != nil }

    // MARK: - Session

    /// Exchanges Apple's identity token for a session and stores it.
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        let session: AuthSession = try await authService.request(
            AppleIDTokenRequest(idToken: idToken, nonce: nonce)
        )
        setSession(session)
        return session
    }

    /// Refreshes the JWT if it's missing, expired, or within `refreshLeeway`
    /// of expiry. No-op if a valid token is cached.
    ///
    /// The app and the AutoFill extension share the session through the
    /// Keychain, so before refreshing it rereads the Keychain: the other one
    /// may have refreshed already, and the auth server rotates the refresh
    /// token, so using an old one could end the session.
    func ensureFresh() async throws {
        if isFresh { return }
        reloadFromKeychain()
        if isFresh { return }
        try await refreshShared()
    }
}

private extension AuthTokenProvider {
    /// Whether the cached access token is valid for longer than `refreshLeeway`.
    var isFresh: Bool {
        guard cachedToken != nil, let cachedExpiresAt else { return false }
        return cachedExpiresAt.timeIntervalSinceNow > refreshLeeway
    }

    /// Picks up a session the other process (app or AutoFill) saved.
    func reloadFromKeychain() {
        cachedToken = KeychainService.loadAccessToken()
        cachedRefreshToken = KeychainService.loadRefreshToken()
        cachedExpiresAt = cachedToken.flatMap(Self.expiry(of:))
    }

    /// The access token's expiry, from the `exp` claim in its payload. The
    /// token isn't verified here; Munin does that.
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        struct Claims: Decodable { let exp: TimeInterval }
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONDecoder().decode(Claims.self, from: data) else { return nil }
        return Date(timeIntervalSince1970: claims.exp)
    }

    /// Caches a new session and saves its tokens to the Keychain.
    func setSession(_ session: AuthSession) {
        cachedToken = session.accessToken
        cachedRefreshToken = session.refreshToken
        cachedExpiresAt = Self.expiry(of: session.accessToken)
            ?? Date().addingTimeInterval(TimeInterval(session.expiresIn))

        KeychainService.saveAccessToken(session.accessToken)
        KeychainService.saveRefreshToken(session.refreshToken)
    }

    /// Coalesces concurrent refresh attempts onto a single in-flight Task.
    func refreshShared() async throws {
        if let inflight = inflightRefresh {
            try await inflight.value
            return
        }
        let task = Task { try await refreshTokenIfPossible() }
        inflightRefresh = task
        defer { inflightRefresh = nil }
        try await task.value
    }

    /// Exchanges the refresh token for a new session.
    ///
    /// If the auth server rejects the refresh token, the session is reset and
    /// `TokenProvidableError.missing` is thrown, which signs the user out.
    func refreshTokenIfPossible() async throws {
        guard let refreshToken = cachedRefreshToken else {
            throw TokenProvidableError.missing
        }
        do {
            let session: AuthSession = try await authService.request(
                RefreshTokenRequest(refreshToken: refreshToken)
            )
            setSession(session)
        } catch {
            if error.invalidatesAuthSession {
                reset()
                throw TokenProvidableError.missing
            }
            throw error
        }
    }
}
