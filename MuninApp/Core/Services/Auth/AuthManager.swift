import AuthenticationServices
import Foundation
import Observation

/// An object that manages Sign in with Apple and the resulting session.
///
/// The user's ID and email are stored in the Keychain; the session tokens are
/// managed by ``AuthTokenProvider``. Views observe ``isSignedIn``.
@Observable
final class AuthManager: UserSession {
    /// The raw nonce of the sign-in in progress, sent with the identity token.
    private var currentNonce: String?
    /// The API used to delete the account.
    private let api: any MuninAPI

    /// A Boolean value that indicates whether a session exists.
    private(set) var isSignedIn: Bool
    /// The signed-in user's email, as provided by Sign in with Apple.
    private(set) var email: String?
    /// The signed-in user's ID, which scopes their data on the server.
    private(set) var userID: String?
    /// A Boolean value that indicates whether the Apple identity token is being exchanged for a session.
    private(set) var isSigningIn = false
    /// The most recent sign-in error.
    private(set) var signInError: String?

    /// The provider that supplies and refreshes access tokens for server requests.
    let tokenProvider: AuthTokenProvider

    /// Creates an authentication manager, restoring the stored session and user.
    ///
    /// - Parameters:
    ///   - tokenProvider: The provider that stores and refreshes session tokens.
    ///   - api: The API used to delete the account.
    init(tokenProvider: AuthTokenProvider = .shared, api: any MuninAPI) {
        self.tokenProvider = tokenProvider
        self.api = api
        isSignedIn = tokenProvider.hasSession
        email = KeychainService.loadEmail()
        userID = KeychainService.loadUserID()
    }
}

extension AuthManager {
    /// Configures a Sign in with Apple request.
    ///
    /// Apple receives the SHA-256 hash of a fresh nonce; the server later
    /// receives the raw nonce to verify the identity token.
    ///
    /// - Parameter request: The request to configure.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Nonce.random()
        currentNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = Nonce.sha256(nonce)
        signInError = nil
    }

    /// Completes Sign in with Apple by exchanging the identity token for a
    /// session and storing the user.
    ///
    /// Canceling isn't treated as an error.
    ///
    /// - Parameter result: The result of the authorization request.
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

    /// Signs out, deleting the session tokens, the stored user, and the AutoFill suggestions.
    func signOut() {
        AutoFillIdentities.removeAll()
        tokenProvider.reset()
        setUser(id: nil, email: nil)
        isSignedIn = false
    }

    /// Deletes the account and all its data, then signs out.
    ///
    /// The user confirms with Sign in with Apple first. Deleting the account
    /// also revokes the Apple tokens.
    ///
    /// - Parameter proof: The master password proof from the unlocked vault.
    /// - Returns: `false` if the user dismissed the Apple sheet and nothing was deleted.
    func deleteAccount(proof: String?) async throws -> Bool {
        let code: String
        do {
            code = try await AppleReauthorization().authorizationCode()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return false
        }
        try await api.deleteAccount(appleAuthorizationCode: code, proof: proof)
        signOut()
        return true
    }
}

private extension AuthManager {
    /// Stores the user's ID and email in memory and in the Keychain; `nil` deletes them.
    func setUser(id: String?, email: String?) {
        userID = id
        self.email = email
        if let id { KeychainService.saveUserID(id) } else { KeychainService.deleteUserID() }
        if let email { KeychainService.saveEmail(email) } else { KeychainService.deleteEmail() }
    }
}
