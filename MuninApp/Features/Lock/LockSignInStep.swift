import AuthenticationServices
import SwiftUI

/// A step that offers Sign in with Apple.
struct LockSignInStep: View {
    /// The sign-in state that handles the Sign in with Apple request.
    @Environment(AuthManager.self) private var auth
    /// The color scheme, which picks the button's style.
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
                if auth.isSigningIn { AccentSpinner(size: DesignKit.Spacing.Primitive.s24) }
            }

            if let onCancel {
                LockButton("global.cancel", style: .tertiary, action: onCancel)
                    #if os(iOS)
                    .frame(maxWidth: .infinity)
                    #endif
            }
        }
    }
}
