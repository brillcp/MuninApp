import AuthenticationServices
import SwiftUI

// Components shared by the lock screen layouts.

/// A view that shows the app's icon, name, and tagline on the lock screen.
struct LockLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s16) {
            Image(colorScheme == .light ? DesignKit.Asset.appIcon : DesignKit.Asset.appIconDark)
                .resizable()
                .scaledToFit()
                .frame(width: DesignKit.Spacing.Primitive.s64)
            Text("main.window.title")
                .font(.title.bold())
                .foregroundStyle(.primary)
            Text("subscription.message")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

/// The steps the lock screen's card can show.
///
/// Each step has its own view. ``LockPanel`` switches between them.
enum LockStep: Hashable {
    /// Sign in with Apple, shown while signed out.
    case signIn
    /// Unlock with Face ID or Touch ID.
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

/// A view that shows the lock screen's card: the title, the current step, and
/// any error.
///
/// Step changes animate. When the vault can't be opened, for example because
/// the server is unreachable, an alert offers to try again or sign out. The
/// card is disabled while work is in progress. After Sign in with Apple,
/// biometric unlock starts automatically once the vault is ready.
struct LockPanel: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    /// The view model that receives the password list during unlock.
    @Environment(VaultViewModel.self) private var vaultModel
    /// The step the user chose, or `nil` to show the default step.
    @State private var chosenStep: LockStep?
    /// A Boolean value that indicates whether to start biometric unlock once the
    /// vault is ready, set after Sign in with Apple.
    @State private var unlocksAfterSignIn = false

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
            if let title = step.title {
                Text(title)
                    .font(.title.bold())
            }

            stepView
                .transition(.blurReplace)

            if auth.isSignedIn {
                if step == .biometrics || step == .masterPassword, let email = auth.email {
                    LockButton(LocalizedKey("lock.switchAccount", email), style: .tertiary) { go(to: .signIn) }
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
        .disabled(isWorking)
        .animation(DesignKit.Motion.bouncy, value: step)
        .onChange(of: auth.userID) { chosenStep = nil }
        .onChange(of: auth.isSigningIn) { wasSigningIn, isSigningIn in
            guard wasSigningIn, !isSigningIn, auth.isSignedIn, auth.signInError == nil else { return }
            chosenStep = nil
            unlocksAfterSignIn = true
            startUnlockIfReady()
        }
        .onChange(of: session.state) { startUnlockIfReady() }
        .alert("errors.openVault.title", item: $session.failureMessage) { _ in
            Button("global.tryAgain") { Task { await session.prepare() } }
            Button("account.signOut", role: .destructive, action: auth.signOut)
        } message: { message in
            Text(message)
        }
    }
}

private extension LockPanel {
    /// The step to show.
    ///
    /// Sign-in while signed out; otherwise the user's choice, then biometrics
    /// when available, then the master password.
    var step: LockStep {
        guard auth.isSignedIn else { return .signIn }
        if let chosenStep { return chosenStep }
        return session.offersBiometricUnlock ? .biometrics : .masterPassword
    }

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

    /// A Boolean value that indicates whether sign-in, unlock, or the vault check
    /// after sign-in is in progress.
    var isWorking: Bool {
        auth.isSigningIn || session.isWorking || (auth.isSignedIn && session.state == .checking)
    }

    /// The sign-in error on the sign-in step; otherwise, the session's error.
    var errorMessage: String? {
        step == .signIn ? auth.signInError : session.errorMessage
    }

    /// Starts biometric unlock after sign-in, once the vault is locked and ready.
    func startUnlockIfReady() {
        guard unlocksAfterSignIn, session.state == .locked else { return }
        unlocksAfterSignIn = false
        if session.offersBiometricUnlock {
            Task { await session.unlockWithBiometrics(prefetchingInto: vaultModel) }
        }
    }

    /// Shows the given step and clears any error.
    ///
    /// - Parameter step: The step to show, or `nil` for the default step.
    func go(to step: LockStep?) {
        session.clearError()
        chosenStep = step
    }
}

// MARK: - Steps

// MARK: - Shared Components

/// A lock screen button that plays a light haptic on tap.
///
/// Use ``Style/primary`` for the main action, ``Style/secondary`` for
/// alternatives such as switching unlock method, ``Style/clear`` for icon
/// buttons on glass, and ``Style/tertiary`` for text links such as Cancel.
struct LockButton: View {
    /// A counter incremented on each tap to trigger the haptic.
    @State private var taps = 0

    /// The title, or `nil` for an icon-only button.
    var title: LocalizedStringKey?
    /// The SF Symbol name, or `nil` for a text-only button.
    let systemImage: String?
    /// The visual style.
    let style: Style
    /// A Boolean value that indicates whether a spinner replaces the label.
    ///
    /// The button keeps its size while loading.
    let isLoading: Bool
    /// The action to perform on tap.
    let action: () -> Void

    /// Creates a button with a title, an icon, or both.
    ///
    /// - Parameters:
    ///   - title: The title, or `nil` for an icon-only button.
    ///   - systemImage: The SF Symbol name, or `nil` for a text-only button.
    ///   - style: The visual style.
    ///   - isLoading: A Boolean value that indicates whether to show a spinner.
    ///   - action: The action to perform on tap.
    init(
        _ title: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        style: Style = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        styled(button)
            .controlSize(.large)
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}

extension LockButton {
    /// The visual styles of a lock screen button.
    enum Style {
        /// Prominent glass, for the main action.
        case primary
        /// Plain glass, for alternatives.
        case secondary
        /// Clear glass, for icon buttons.
        case clear
        /// Plain text without glass.
        case tertiary
    }
}

private extension LockButton {
    /// The unstyled button.
    ///
    /// Its width comes from the `buttonSizing` set by the lock screen layout.
    var button: some View {
        Button {
            taps += 1
            action()
        } label: {
            label
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.primary)
                    }
                }
        }
        .animation(DesignKit.Motion.linear, value: isLoading)
    }

    @ViewBuilder
    var label: some View {
        if let title, let systemImage {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .font(.title2)
            }
        } else if let title {
            Text(title)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.title2)
        }
    }

    /// Applies the button's style.
    ///
    /// Each glass style is a distinct type, so each is applied in its own branch.
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

/// A view that shows the app's version on the lock screen.
struct LockVersionLabel: View {
    var body: some View {
        Text(LocalizedKey("lock.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
            .font(.footnote)
            .foregroundStyle(.primary)
            .padding(.leading)
    }
}
