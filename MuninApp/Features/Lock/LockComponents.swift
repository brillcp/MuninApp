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
                .frame(width: 38, height: 38)
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
    /// After Sign in with Apple: start Face ID / Touch ID once the vault is ready.
    @State private var unlocksAfterSignIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(step.title)
                .font(.title.bold())

            if auth.isSignedIn {
                LockAccountRow(email: auth.email)
                if step != .signIn {
                    // Shows Sign in with Apple; the current account stays signed
                    // in until another one signs in.
                    LockSecondaryButton("lock.switchAccount") { go(to: .signIn) }
                }
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
        .glassEffect(in: .rect(cornerRadius: 24))
        .disabled(isWorking)
        .animation(.bouncy, value: step)
        .animation(.bouncy, value: isWorking)
        // A new account (or signing out) starts from its default step.
        .onChange(of: auth.userID) { chosenStep = nil }
        // A finished sign-in (also the same account again, after "Switch
        // account") goes back to unlocking and starts biometrics.
        .onChange(of: auth.isSigningIn) { wasSigningIn, isSigningIn in
            guard wasSigningIn, !isSigningIn, auth.isSignedIn, auth.signInError == nil else { return }
            chosenStep = nil
            unlocksAfterSignIn = true
            startUnlockIfReady()
        }
        // A new account is checked first; unlock once it's locked and ready.
        .onChange(of: session.state) { startUnlockIfReady() }
    }

    private var step: LockStep {
        guard auth.isSignedIn else { return .signIn }
        if let chosenStep { return chosenStep }
        return session.offersBiometricUnlock ? .biometrics : .masterPassword
    }

    @ViewBuilder
    private var stepView: some View {
        switch step {
        case .signIn:
            // Signed in already means "Switch account": offer a way back.
            LockSignInStep(onCancel: auth.isSignedIn ? { go(to: nil) } : nil)
        case .biometrics:
            LockBiometricsStep(stacksButtons: stacksButtons) { go(to: .masterPassword) }
        case .masterPassword:
            LockMasterPasswordStep(
                // Focus the field when the user chose this step, not when it's
                // the default (so the iOS keyboard doesn't pop up at launch).
                focusesField: chosenStep == .masterPassword,
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

    private func startUnlockIfReady() {
        guard unlocksAfterSignIn, session.state == .locked else { return }
        unlocksAfterSignIn = false
        if session.offersBiometricUnlock {
            Task { await session.unlockWithBiometrics() }
        }
    }

    /// `nil` goes back to the default step.
    private func go(to step: LockStep?) {
        session.clearError()
        chosenStep = step
    }
}

// MARK: - Steps

/// Signed out: Sign in with Apple.
private struct LockSignInStep: View {
    /// Set when switching account, to go back to unlocking.
    var onCancel: (() -> Void)?

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
            .controlSize(.large)

            if let onCancel {
                LockSecondaryButton("global.cancel", action: onCancel)
            }
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
    let focusesField: Bool
    let onUseBiometrics: (() -> Void)?
    let onForgotPassword: () -> Void

    @Environment(VaultSession.self) private var session
    @State private var password = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SecureField("lock.masterPassword.placeholder", text: $password)
                .focused($isFieldFocused)
                .task { if focusesField { isFieldFocused = true } }
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
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("lock.recovery.message")
                .foregroundStyle(.secondary)
            TextField("vaultKey.missing.placeholder", text: $recoveryKey, axis: .vertical)
                .focused($isFieldFocused)
                // Only reachable via "Forgot master password?", so always focus.
                .task { isFieldFocused = true }
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
            #if os(iOS)
            // Readable on the iOS artwork background.
            .shadow(color: .black, radius: 2)
            #endif
            .padding(.leading)
    }
}
