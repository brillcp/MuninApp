import Foundation
import Networking

/// Holds the Supabase session from Sign in with Apple and supplies its JWT as
/// the bearer token for Munin.
///
/// JWTs are short-lived (~1h). Callers `await ensureFresh()` before a request;
/// a missing, expired or nearly expired JWT is exchanged for a new pair using
/// the stored refresh token. Tokens persist in the Keychain.
final class SupabaseTokenProvider: TokenProvidable {
    static let shared = SupabaseTokenProvider()

    private var cachedToken: String?
    private var cachedRefreshToken: String?
    private var cachedExpiresAt: Date?

    /// Refresh slightly before actual expiry so an in-flight request doesn't
    /// race the boundary.
    private let refreshLeeway: TimeInterval = 30

    /// In-flight refresh shared by concurrent callers. Supabase rotates the
    /// refresh token on every exchange, so two parallel refreshes would race.
    private var inflightRefresh: Task<Void, Error>?

    private let authService: Network.Service

    init() {
        cachedToken = KeychainService.loadSupabaseToken()
        cachedRefreshToken = KeychainService.loadSupabaseRefreshToken()
        cachedExpiresAt = UserDefaults.standard.object(forKey: Self.expiryKey) as? Date

        let server = ServerConfig(
            baseURL: APIConfig.authBaseURL,
            additionalHeaders: ["apikey": APIConfig.anonKey],
            tokenProvider: nil
        )
        authService = Network.Service(server: server, logger: nil)
    }
}

extension SupabaseTokenProvider {
    var token: Result<String, TokenProvidableError> {
        guard let cachedToken else { return .failure(.missing) }
        return .success(cachedToken)
    }

    func setToken(_ token: String) {
        cachedToken = token
    }

    func reset() {
        cachedToken = nil
        cachedRefreshToken = nil
        cachedExpiresAt = nil
        UserDefaults.standard.removeObject(forKey: Self.expiryKey)
        KeychainService.deleteSupabaseToken()
        KeychainService.deleteSupabaseRefreshToken()
    }

    var hasSession: Bool { cachedRefreshToken != nil }

    // MARK: - Session

    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseSession {
        let session: SupabaseSession = try await authService.request(
            AppleIDTokenRequest(idToken: idToken, nonce: nonce)
        )
        setSession(session)
        return session
    }

    /// Refreshes the JWT if it's missing, expired, or within `refreshLeeway`
    /// of expiry. No-op if a valid token is cached.
    func ensureFresh() async throws {
        if cachedToken != nil,
           let cachedExpiresAt,
           cachedExpiresAt.timeIntervalSinceNow > refreshLeeway {
            return
        }
        try await refreshShared()
    }
}

private extension SupabaseTokenProvider {
    static let expiryKey = "supabase.token.expires_at"

    func setSession(_ session: SupabaseSession) {
        cachedToken = session.accessToken
        cachedRefreshToken = session.refreshToken
        let expiresAt = Date().addingTimeInterval(TimeInterval(session.expiresIn))
        cachedExpiresAt = expiresAt

        KeychainService.saveSupabaseToken(session.accessToken)
        KeychainService.saveSupabaseRefreshToken(session.refreshToken)
        UserDefaults.standard.set(expiresAt, forKey: Self.expiryKey)
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

    func refreshTokenIfPossible() async throws {
        guard let refreshToken = cachedRefreshToken else {
            throw TokenProvidableError.missing
        }
        do {
            let session: SupabaseSession = try await authService.request(
                RefreshTokenRequest(refreshToken: refreshToken)
            )
            setSession(session)
        } catch {
            if error.invalidatesSupabaseSession {
                reset()
                throw TokenProvidableError.missing
            }
            throw error
        }
    }
}
