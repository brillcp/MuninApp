import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "key.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("signIn.title")
                    .font(.largeTitle.bold())
                Text("signIn.subtitle")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                auth.prepare(request)
            } onCompletion: { result in
                Task { await auth.complete(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .clipShape(.capsule)
            .frame(maxWidth: 320)
            .frame(height: 44)
            .disabled(auth.isSigningIn)
            .overlay {
                if auth.isSigningIn { ProgressView() }
            }

            if let error = auth.signInError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}

#Preview {
    SignInView()
        .environment(AuthManager())
}
