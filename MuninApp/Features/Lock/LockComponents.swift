import AuthenticationServices
import SwiftUI

// Pieces shared by the Mac and iOS lock screens (LockView+macOS / LockView+iOS).

/// The app's logo and name, shown at the top left of the Mac lock screen.
/// The image comes from the "Logo" image set.
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
    /// Signed out: Sign in with Apple.
    case signIn
    /// Unlock with Face ID / Touch ID.
    case biometrics
    /// Unlock with the master password.
    case masterPassword
    /// Reset a forgotten master password with the recovery key.
    case recoveryKey

    /// The card's title for this step.
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
///
/// Changing step animates with a bounce. If the vault couldn't be opened
/// (Munin unreachable, for example), an alert offers Try Again and Sign Out. While something is working, a
/// spinner takes the place of the step's buttons. Right after Sign in with
/// Apple, Face ID / Touch ID starts on its own once the vault is ready.
struct LockPanel: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    /// Set when the user picks another way to unlock; nil means the default.
    @State private var chosenStep: LockStep?
    /// After Sign in with Apple: start Face ID / Touch ID once the vault is ready.
    @State private var unlocksAfterSignIn = false

    var body: some View {
        @Bindable var session = session
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
        .animation(DesignKit.Motion.bouncy, value: step)
        .animation(DesignKit.Motion.bouncy, value: isWorking)
        .onChange(of: auth.userID) { chosenStep = nil }
        .onChange(of: auth.isSigningIn) { wasSigningIn, isSigningIn in
            guard wasSigningIn, !isSigningIn, auth.isSignedIn, auth.signInError == nil else { return }
            chosenStep = nil
            unlocksAfterSignIn = true
            startUnlockIfReady()
        }
        .onChange(of: session.state) { startUnlockIfReady() }
        .alert("errors.openVault.title", item: $session.failureMessage) { _ in
            Button("global.tryAgain") { Task { await session.prepare(auth: auth) } }
            Button("account.signOut", role: .destructive) { auth.signOut() }
        } message: { message in
            Text(message)
        }
    }
}

private extension LockPanel {
    /// The step to show: sign-in while signed out, else the user's choice,
    /// else biometrics when offered, else the master password.
    var step: LockStep {
        guard auth.isSignedIn else { return .signIn }
        if let chosenStep { return chosenStep }
        return session.offersBiometricUnlock ? .biometrics : .masterPassword
    }

    /// The current step's view.
    @ViewBuilder
    var stepView: some View {
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

    /// True while signing in, unlocking, or checking the vault after sign-in.
    var isWorking: Bool {
        auth.isSigningIn || session.isWorking || (auth.isSignedIn && session.state == .checking)
    }

    /// The sign-in error on the sign-in step, otherwise the session's error.
    var errorMessage: String? {
        step == .signIn ? auth.signInError : session.errorMessage
    }

    /// Starts Face ID / Touch ID once, after a sign-in, when the vault has
    /// reached the locked state.
    func startUnlockIfReady() {
        guard unlocksAfterSignIn, session.state == .locked else { return }
        unlocksAfterSignIn = false
        if session.offersBiometricUnlock {
            Task { await session.unlockWithBiometrics() }
        }
    }

    /// Moves to `step` and clears the error. `nil` goes back to the default step.
    func go(to step: LockStep?) {
        session.clearError()
        chosenStep = step
    }
}

// MARK: - Steps

/// Signed out: Sign in with Apple.
private struct LockSignInStep: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    /// Set when switching account, to go back to unlocking.
    var onCancel: (() -> Void)?

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
    @Environment(VaultSession.self) private var session

    /// Called by the master password button.
    let onUseMasterPassword: () -> Void

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
    @Environment(VaultSession.self) private var session
    /// The typed master password, cleared as soon as it's submitted.
    @State private var password = ""
    /// Whether the password field has keyboard focus.
    @FocusState private var isFieldFocused: Bool

    /// Focuses the field on appear: true when the user chose this step
    /// rather than landing on it by default.
    let focusesField: Bool
    /// Called by the biometrics button; nil hides it.
    let onUseBiometrics: (() -> Void)?
    /// Called by "Forgot master password?".
    let onForgotPassword: () -> Void

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

    /// Clears the field and unlocks with what was typed.
    private func unlock() {
        guard !password.isEmpty else { return }
        let entered = password
        password = ""
        Task { await session.unlock(masterPassword: entered) }
    }
}

/// Recovery key, then a new master password (VaultSession moves on to setup).
///
/// Only reachable through "Forgot master password?", so the field is always
/// focused on appear.
private struct LockRecoveryKeyStep: View {
    @Environment(VaultSession.self) private var session
    /// The typed or pasted recovery key.
    @State private var recoveryKey = ""
    /// Whether the recovery key field has keyboard focus.
    @FocusState private var isFieldFocused: Bool

    /// Called by Cancel.
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
            Text("lock.recovery.message")
                .foregroundStyle(.secondary)
            TextField("vaultKey.missing.placeholder", text: $recoveryKey, axis: .vertical)
                .focused($isFieldFocused)
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

/// Lock screen button, with a light haptic on tap.
///
/// `.primary` for the main action (prominent glass), `.secondary` for
/// alternatives like switching method, `.tertiary` for plain text links such
/// as forgot password or cancel.
struct LockButton: View {
    /// The button's look.
    enum Style {
        /// Prominent glass, for the main action.
        case primary
        /// Plain glass, for alternatives.
        case secondary
        /// Clear glass
        case clear
        /// No glass, just plain text.
        case tertiary
    }

    /// Bumped on every tap, to trigger the haptic.
    @State private var taps = 0

    /// The button's text; nil for an icon-only button.
    var title: LocalizedStringKey? = nil
    /// The button's SF Symbol; nil for a text-only button.
    let systemImage: String?
    /// The button's look.
    let style: Style
    /// Runs on tap.
    let action: () -> Void

    /// Creates a button with a title, an icon, or both.
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
}

private extension LockButton {
    /// The unstyled button: title and/or icon, full width on iOS.
    var button: some View {
        Button {
            taps += 1
            action()
        } label: {
            if let title, let systemImage {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .font(.title2)
                }
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
                    .font(.title2)
            }
        }
    }

    /// Applies the style. The glass styles are different types, so branch
    /// rather than pick one inline.
    @ViewBuilder
    func styled(_ button: some View) -> some View {
        switch style {
        case .primary:
            button.buttonStyle(.glassProminent)
        case .secondary:
            button
                .buttonStyle(.glass)
                .tint(.primary)
        case .clear:
            button
                .padding(DesignKit.Spacing.Primitive.s6)
                .glassEffect()
                .foregroundStyle(.primary)
        case .tertiary:
            button
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
        }
    }
}

/// "Signed in as" and the signed-in email, on one line.
struct LockAccountRow: View {
    /// The signed-in email; nil shows nothing.
    let email: String?

    var body: some View {
        if let email {
            Text("Signed in as: \(email)")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.callout)
        }
    }
}

private extension LockAccountRow {
    /// The email's first two letters, capitalised.
    var initials: String {
        String((email ?? "").prefix(2)).capitalized
    }
}

/// The app's version, at the bottom of the lock screen.
///
/// On iOS it gets a shadow so it stays readable on the artwork background.
struct LockVersionLabel: View {
    var body: some View {
        Text(LocalizedKey("lock.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
            .font(.footnote)
            .foregroundStyle(.primary)
            .padding(.leading)
    }
}
