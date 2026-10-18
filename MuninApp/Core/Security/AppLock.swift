import Foundation
import LocalAuthentication
import Observation

/// Asks for Face ID / Touch ID once, when the app starts.
@Observable
final class AppLock {
    private(set) var isUnlocked = false
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?

    func unlock() async {
        guard !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            isUnlocked = try await LAContext().evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your authenticator codes"
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
