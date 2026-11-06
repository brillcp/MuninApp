import AuthenticationServices
import SwiftUI

/// A step that offers Sign in with Apple.
struct LockSignInStep: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    /// The action that returns to unlocking, or `nil` to hide Cancel.
    ///
    /// Set when switching accounts.
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
            SignInWithAppleButton(.signIn) { request in
                auth.prepare(request)
            } onCompletion: { result in
                Task { await auth.complete(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity, maxHeight: DesignKit.Spacing.Primitive.s56)
            .controlSize(.large)
            .clipShape(.capsule)
            .opacity(auth.isSigningIn ? 0.6 : 1)
            .overlay {
                if auth.isSigningIn { ProgressView().tint(.primary) }
            }

            if let onCancel {
                LockButton("global.cancel", style: .tertiary, action: onCancel)
            }
        }
    }
}
