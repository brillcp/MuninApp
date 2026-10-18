import AuthenticationServices
import Foundation
import Observation

/// Sign in with Apple → Supabase session. Views observe `isSignedIn`.
@Observable
final class AuthManager {
    private(set) var isSignedIn: Bool
    private(set) var email: String?
    /// Supabase user ID; Munin scopes the user's accounts to it.
    private(set) var userID: String?
    private(set) var isSigningIn = false
    private(set) var signInError: String?

    let tokenProvider: SupabaseTokenProvider
    private var currentNonce: String?

    init(tokenProvider: SupabaseTokenProvider = .shared) {
        self.tokenProvider = tokenProvider
        isSignedIn = tokenProvider.hasSession
        Self.moveUserFromUserDefaults()
        email = KeychainService.loadEmail()
        userID = KeychainService.loadUserID()
    }

    /// Earlier builds kept the email and user ID in UserDefaults. Move them to
    /// the Keychain once, so existing sessions keep working.
    private static func moveUserFromUserDefaults() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "munin.user.id") {
            if KeychainService.loadUserID() == nil { KeychainService.saveUserID(id) }
            defaults.removeObject(forKey: "munin.user.id")
        }
        if let email = defaults.string(forKey: "munin.user.email") {
            if KeychainService.loadEmail() == nil { KeychainService.saveEmail(email) }
            defaults.removeObject(forKey: "munin.user.email")
        }
    }

    /// Configures the Apple request. Apple gets the SHA-256 of a fresh nonce;
    /// Supabase later gets the raw nonce to match against the identity token.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Nonce.random()
        currentNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = Nonce.sha256(nonce)
        signInError = nil
    }

    func complete(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            signInError = error.localizedDescription

        case .success(let authorization):
            guard APIConfig.isAnonKeyConfigured else {
                signInError = "Set APIConfig.anonKey to your Supabase publishable key."
                return
            }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                signInError = "Apple didn't return an identity token. Try again."
                return
            }

            isSigningIn = true
            defer { isSigningIn = false }
            do {
                let session = try await tokenProvider.signInWithApple(idToken: idToken, nonce: nonce)
                setUser(id: session.user?.id, email: session.user?.email ?? credential.email)
                isSignedIn = true
                signInError = nil
            } catch {
                signInError = "Supabase sign-in failed. \(error.localizedDescription)"
            }
        }
    }

    func signOut() {
        tokenProvider.reset()
        setUser(id: nil, email: nil)
        isSignedIn = false
    }

    private func setUser(id: String?, email: String?) {
        userID = id
        self.email = email
        if let id { KeychainService.saveUserID(id) } else { KeychainService.deleteUserID() }
        if let email { KeychainService.saveEmail(email) } else { KeychainService.deleteEmail() }
    }
}
