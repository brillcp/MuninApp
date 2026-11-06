import AuthenticationServices
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// An object that requests a fresh Sign in with Apple authorization code.
///
/// Account deletion uses the code so the server can exchange it for the
/// user's Apple tokens and revoke them, as Apple requires.
final class AppleReauthorization: NSObject {
    /// The continuation that ``authorizationCode()`` awaits.
    private var continuation: CheckedContinuation<String, any Error>?
    /// The controller, retained while the sheet is visible.
    private var controller: ASAuthorizationController?
}

// MARK: - Public API
extension AppleReauthorization {
    /// Presents the Sign in with Apple sheet and returns the authorization code.
    ///
    /// - Throws: `ASAuthorizationError.canceled` if the user dismisses the sheet.
    func authorizationCode() async throws -> String {
        let controller = ASAuthorizationController(authorizationRequests: [ASAuthorizationAppleIDProvider().createRequest()])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AppleReauthorization: ASAuthorizationControllerDelegate {
    /// Resumes with the authorization code, or fails if the credential has none.
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.authorizationCode,
              let code = String(data: data, encoding: .utf8) else {
            finish(.failure(ASAuthorizationError(.failed)))
            return
        }
        finish(.success(code))
    }

    /// Resumes with the error, such as when the user cancels.
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        finish(.failure(error))
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AppleReauthorization: ASAuthorizationControllerPresentationContextProviding {
    /// Returns the key window as the sheet's anchor.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        guard let scene = scenes.first else { preconditionFailure("Sign in with Apple requires a connected window scene.") }
        return UIWindow(windowScene: scene)
        #else
        return NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow()
        #endif
    }
}

// MARK: - Private
private extension AppleReauthorization {
    /// Resumes the pending continuation, at most once.
    func finish(_ result: Result<String, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}
