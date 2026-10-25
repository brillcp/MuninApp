import AuthenticationServices
import Foundation
import Observation

/// Sign in with Apple, exchanged for a session. Views observe `isSignedIn`.
///
/// The user's ID and email are kept in the Keychain; the session tokens are
/// held by `AuthTokenProvider`.
@Observable
final class AuthManager {
    /// Whether a session exists.
    private(set) var isSignedIn: Bool
    /// The signed-in user's email, as given by Sign in with Apple.
    private(set) var email: String?
    /// User ID; Munin scopes the user's data to it.
    private(set) var userID: String?
    /// True while the Apple identity token is being exchanged with the auth server.
    private(set) var isSigningIn = false
    /// The last sign-in error, shown on the sign-in step.
    private(set) var signInError: String?

    /// Supplies and refreshes the JWT for requests to Munin.
    let tokenProvider: AuthTokenProvider
    /// The raw nonce of the sign-in in progress, sent to the auth server with the identity token.
    private var currentNonce: String?

    /// Restores the signed-in state, email and user ID from the previous launch.
    init(tokenProvider: AuthTokenProvider = .shared) {
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
    /// The auth server later gets the raw nonce to match against the identity token.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Nonce.random()
        currentNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = Nonce.sha256(nonce)
        signInError = nil
    }

    /// Finishes Sign in with Apple: exchanges the identity token for a
    /// session and stores the user. Cancelling is not an error.
    func complete(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            signInError = error.localizedDescription

        case .success(let authorization):
            guard APIConfig.isAnonKeyConfigured else {
                signInError = Localized("signIn.error.missingAnonKey")
                return
            }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                signInError = Localized("signIn.error.noIdentityToken")
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
                signInError = Localized("signIn.error.failed", error.localizedDescription)
            }
        }
    }

    /// Deletes the session tokens and the stored user.
    func signOut() {
        tokenProvider.reset()
        setUser(id: nil, email: nil)
        isSignedIn = false
    }

    /// Stores the user's ID and email in memory and in the Keychain (nil deletes them).
    private func setUser(id: String?, email: String?) {
        userID = id
        self.email = email
        if let id { KeychainService.saveUserID(id) } else { KeychainService.deleteUserID() }
        if let email { KeychainService.saveEmail(email) } else { KeychainService.deleteEmail() }
    }
}
