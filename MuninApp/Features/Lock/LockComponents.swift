import AuthenticationServices
import SwiftUI

// Pieces shared by the Mac and iOS lock screens (LockView+macOS / LockView+iOS).

/// App logo and name, top left. Add the logo image to the "Logo" image set.
struct LockLogo: View {
    var body: some View {
        HStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            Text("main.window.title")
                .font(.title2.bold())
                .foregroundStyle(.primary)
        }
    }
}

/// What the lock screen's card shows. Each step is its own view; `LockPanel`
/// is the only place that switches between them.
enum LockStep: Hashable {
    case signIn
    case biometrics
    case masterPassword
    case recoveryKey

    var title: LocalizedStringKey {
        switch self {
        case .signIn:         "lock.step.signIn"
        case .biometrics:     "lock.title"
        case .masterPassword: "lock.step.masterPassword"
        case .recoveryKey:    "lock.step.recoveryKey"
        }
    }
}

/// The lock screen's card: title, account and the current step.
/// Changing step animates with a bounce.
struct LockPanel: View {
    /// iOS stacks the biometrics buttons; the Mac puts them side by side.
    var stacksButtons = false

    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    /// Set when the user picks another way to unlock; nil means the default.
    @State private var chosenStep: LockStep?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(step.title)
                .font(.title.bold())

            if auth.isSignedIn {
                LockAccountRow(email: auth.email)
            }

            if isWorking {
                ProgressView()
            }

            stepView
                .transition(.blurReplace)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isWorking)
        .animation(.bouncy, value: step)
        .onChange(of: auth.isSignedIn) { chosenStep = nil }
    }

    private var step: LockStep {
        guard auth.isSignedIn else { return .signIn }
        if let chosenStep, chosenStep != .signIn { return chosenStep }
        return session.offersBiometricUnlock ? .biometrics : .masterPassword
    }

    @ViewBuilder
    private var stepView: some View {
        switch step {
        case .signIn:
            LockSignInStep()
        case .biometrics:
            LockBiometricsStep(stacksButtons: stacksButtons) { go(to: .masterPassword) }
        case .masterPassword:
            LockMasterPasswordStep(
                onUseBiometrics: session.offersBiometricUnlock ? { go(to: .biometrics) } : nil,
                onForgotPassword: { go(to: .recoveryKey) }
            )
        case .recoveryKey:
            LockRecoveryKeyStep { go(to: .masterPassword) }
        }
    }

    private var isWorking: Bool {
        auth.isSigningIn || session.isWorking || (auth.isSignedIn && session.state == .checking)
    }

    private var errorMessage: String? {
        step == .signIn ? auth.signInError : session.errorMessage
    }

    private func go(to step: LockStep) {
        session.clearError()
        chosenStep = step
    }
}

// MARK: - Steps

/// Signed out: Sign in with Apple.
private struct LockSignInStep: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("signIn.subtitle")
                .foregroundStyle(.secondary)

            SignInWithAppleButton(.signIn) { request in
                auth.prepare(request)
            } onCompletion: { result in
                Task { await auth.complete(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .clipShape(.capsule)
        }
    }
}

/// Face ID / Touch ID, with the master password as the alternative.
private struct LockBiometricsStep: View {
    let stacksButtons: Bool
    let onUseMasterPassword: () -> Void

    @Environment(VaultSession.self) private var session

    var body: some View {
        layout {
            LockPrimaryButton("lock.unlockWithBiometrics", systemImage: "touchid") {
                Task { await session.unlockWithBiometrics() }
            }
            LockSecondaryButton("lock.useMasterPassword", action: onUseMasterPassword)
        }
    }

    private var layout: AnyLayout {
        stacksButtons
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
            : AnyLayout(HStackLayout(spacing: 16))
    }
}

/// Master password field. Offers biometrics (if available) and the recovery key.
private struct LockMasterPasswordStep: View {
    let onUseBiometrics: (() -> Void)?
    let onForgotPassword: () -> Void

    @Environment(VaultSession.self) private var session
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SecureField("lock.masterPassword.placeholder", text: $password)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textContentType(.password)
                #endif
                .onSubmit(unlock)
                .colorScheme(.light)

            LockPrimaryButton("lock.unlock", action: unlock)
                .disabled(password.isEmpty)

            if let onUseBiometrics {
                LockSecondaryButton("lock.useBiometrics", action: onUseBiometrics)
            }
            LockSecondaryButton("lock.forgotMasterPassword", action: onForgotPassword)
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        let entered = password
        password = ""
        Task { await session.unlock(masterPassword: entered) }
    }
}

/// Recovery key, then a new master password (VaultSession moves on to setup).
private struct LockRecoveryKeyStep: View {
    let onCancel: () -> Void

    @Environment(VaultSession.self) private var session
    @State private var recoveryKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("lock.recovery.message")
                .foregroundStyle(.secondary)
            TextField("vaultKey.missing.placeholder", text: $recoveryKey, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .colorScheme(.light)

            LockPrimaryButton("lock.recovery.continue") { session.unlock(recoveryKey: recoveryKey) }
                .disabled(recoveryKey.isEmpty)
            LockSecondaryButton("global.cancel", action: onCancel)
        }
    }
}

// MARK: - Shared pieces

/// The main action: full width, filled with the accent color.
struct LockPrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

/// Alternative actions (switch method, forgot password, cancel): plain white text.
struct LockSecondaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .tint(.primary)
    }
}

/// Initials avatar, email and "Switch account" (signs out).
struct LockAccountRow: View {
    let email: String?

    var body: some View {
        if let email {
            HStack {
                Text(verbatim: initials)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.accent, in: .circle)
                Text(email)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var initials: String {
        String((email ?? "").prefix(2)).capitalized
    }
}

struct LockVersionLabel: View {
    var body: some View {
        Text(LocalizedKey("lock.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
            .font(.footnote)
            .foregroundStyle(.primary)
            .shadow(color: .black, radius: 2)
            .padding(.leading)
    }
}
