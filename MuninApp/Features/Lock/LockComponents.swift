import AuthenticationServices
import SwiftUI

// Pieces shared by the Mac and iOS lock screens (LockView+macOS / LockView+iOS).

/// App logo and name, top left. Add the logo image to the "Logo" image set.
struct LockLogo: View {
    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s16) {
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

    var title: LocalizedStringKey? {
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
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    /// Set when the user picks another way to unlock; nil means the default.
    @State private var chosenStep: LockStep?
    /// After Sign in with Apple: start Face ID / Touch ID once the vault is ready.
    @State private var unlocksAfterSignIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
            if let title = step.title {
                Text(title)
                    .font(.title.bold())
            }

            if isWorking {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .transition(.blurReplace)
                    .tint(.white)
            } else {
                stepView
                    .transition(.blurReplace)
            }

            if auth.isSignedIn {
                if step == .biometrics || step == .masterPassword, let email = auth.email {
                    LockButton("\(email) · Switch", style: .tertiary) { go(to: .signIn) }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
        .glassEffect(in: .rect(cornerRadius: 24))
        #endif
        .disabled(isWorking)
        .animation(.bouncy, value: step)
        .animation(.bouncy, value: isWorking)
        .onChange(of: auth.userID) { chosenStep = nil }
        .onChange(of: auth.isSigningIn) { wasSigningIn, isSigningIn in
            guard wasSigningIn, !isSigningIn, auth.isSignedIn, auth.signInError == nil else { return }
            chosenStep = nil
            unlocksAfterSignIn = true
            startUnlockIfReady()
        }
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
            LockSignInStep(onCancel: auth.isSignedIn ? { go(to: nil) } : nil)
        case .biometrics:
            LockBiometricsStep { go(to: .masterPassword) }
        case .masterPassword:
            LockMasterPasswordStep(
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
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
            Text("signIn.subtitle")

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
                LockButton("global.cancel", style: .tertiary, action: onCancel)
            }
        }
    }
}

/// Face ID / Touch ID, with the master password as the alternative.
private struct LockBiometricsStep: View {
    let onUseMasterPassword: () -> Void

    @Environment(VaultSession.self) private var session

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s16) {
            #if os(macOS)
            LockButton("settings.biometrics.touch", systemImage: "touchid") {
                Task { await session.unlockWithBiometrics() }
            }
            #else
            LockButton("settings.biometrics.face", systemImage: "faceid") {
                Task { await session.unlockWithBiometrics() }
            }
            #endif

            LockButton(systemImage: "lock.shield.fill", style: .secondary, action: onUseMasterPassword)
        }
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
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
            SecureField("lock.masterPassword.placeholder", text: $password)
                .focused($isFieldFocused)
                .task { if focusesField { isFieldFocused = true } }
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textContentType(.password)
                #endif
                .onSubmit(unlock)
                .colorScheme(.light)

            HStack {
                LockButton("lock.unlock", action: unlock)
                    .disabled(password.isEmpty)

                if let onUseBiometrics {
                    #if os(iOS)
                    LockButton(systemImage: "faceid", style: .secondary, action: onUseBiometrics)
                    #else
                    LockButton(systemImage: "touchid", style: .secondary, action: onUseBiometrics)
                    #endif
                }
            }
            LockButton("lock.forgotMasterPassword", style: .tertiary, action: onForgotPassword)
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
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
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

            LockButton("lock.recovery.continue") { session.unlock(recoveryKey: recoveryKey) }
                .disabled(recoveryKey.isEmpty)
            LockButton("global.cancel", style: .tertiary, action: onCancel)
        }
    }
}

// MARK: - Shared pieces

/// Lock screen button. `.primary` for the main action (prominent glass),
/// `.secondary` for alternatives like switch method, forgot password or cancel,
/// `.tertiary` for plain text links.
struct LockButton: View {
    enum Style {
        case primary
        case secondary
        /// No glass, just plain text.
        case tertiary
    }

    @State private var taps = 0

    var title: LocalizedStringKey? = nil
    let systemImage: String?
    let style: Style
    let action: () -> Void

    init(
        _ title: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        style: Style = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    var body: some View {
        styled(button)
            .controlSize(.large)
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private var button: some View {
        Button {
            taps += 1
            action()
        } label: {
            if let title, let systemImage {
                Label(title, systemImage: systemImage)
                    #if os(iOS)
                    .frame(maxWidth: .infinity)
                    #endif
            } else if let title {
                Text(title)
                    #if os(iOS)
                    .frame(maxWidth: .infinity)
                    #endif
            } else if let systemImage {
                Image(systemName: systemImage)
            }
        }
    }

    /// The glass styles are different types, so branch rather than pick one inline.
    @ViewBuilder
    private func styled(_ button: some View) -> some View {
        switch style {
        case .primary:
            button.buttonStyle(.glassProminent)
        case .secondary:
            button
                .buttonStyle(.glass)
                .tint(.primary)
        case .tertiary:
            button
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
        }
    }
}

/// Initials avatar, email and "Switch account" (signs out).
struct LockAccountRow: View {
    let email: String?

    var body: some View {
        if let email {
            Text("Signed in as: \(email)")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.callout)
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
