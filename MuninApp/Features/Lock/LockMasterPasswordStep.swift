import SwiftUI

/// A step that unlocks with the master password, with options to use
/// biometrics or the recovery key.
///
/// On iPhone, and on iPad in a compact-width window, Forgot Password is an
/// icon beside the field, and the buttons fill the row below it. On macOS and
/// in a regular-width iPad window, Forgot Password is a text button at the
/// trailing end of the button row.
///
/// While unlocking, a spinner replaces the Unlock button's title on iOS, and
/// sits to the right of the buttons on macOS.
struct LockMasterPasswordStep: View {
    #if os(iOS)
    /// The horizontal size class, which picks the compact or regular layout.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// The vault session to unlock.
    @Environment(VaultSession.self) private var session
    /// The view model that receives the password list during unlock.
    @Environment(VaultViewModel.self) private var vaultModel
    /// The entered master password, cleared on submit.
    @State private var password = ""
    /// A Boolean value that indicates whether the password field has focus.
    @FocusState private var isFieldFocused: Bool

    /// A Boolean value that indicates whether to focus the field on appear.
    ///
    /// True when the user chose this step instead of landing on it by default.
    let focusesField: Bool
    /// The action that switches to biometric unlock, or `nil` to hide the button.
    let onUseBiometrics: (() -> Void)?
    /// The action that switches to the recovery key step.
    let onForgotPassword: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
            HStack(spacing: DesignKit.Spacing.Primitive.s12) {
                SecureField("lock.masterPassword.placeholder", text: $password)
                    .focused($isFieldFocused)
                    .task(focusFieldIfChosen)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textContentType(.password)
                    #endif
                    .onSubmit(unlock)
                    .colorScheme(.light)

                if usesCompactLayout {
                    LockButton(systemImage: DesignKit.Icon.forgotPassword, style: .clear, action: onForgotPassword)
                        .accessibilityLabel(Text("lock.forgotMasterPassword"))
                }
            }

            HStack {
                LockButton("lock.unlock", isLoading: showsButtonSpinner, action: unlock)
                    .disabled(password.isEmpty)

                if let onUseBiometrics {
                    LockButton(
                        systemImage: session.usesFaceID ? DesignKit.Icon.faceID : DesignKit.Icon.touchID,
                        style: .secondary,
                        action: onUseBiometrics
                    )
                    .buttonSizing(.fitted)
                }
                #if os(macOS)
                if isUnlocking {
                    AccentSpinner(size: DesignKit.Spacing.Primitive.s16)
                        .transition(.opacity)
                }
                #endif

                if !usesCompactLayout {
                    Spacer()
                    LockButton("lock.forgotMasterPassword", style: .tertiary, action: onForgotPassword)
                }
            }
            .animation(DesignKit.Motion.linear, value: isUnlocking)
        }
    }
}

private extension LockMasterPasswordStep {
    /// A Boolean value that indicates whether the compact layout is used: on
    /// iPhone, and on iPad in a compact-width window.
    var usesCompactLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// Focuses the field when the user chose this step.
    func focusFieldIfChosen() {
        if focusesField { isFieldFocused = true }
    }

    /// A Boolean value that indicates whether an unlock or vault check is in progress.
    var isUnlocking: Bool {
        session.isWorking || session.state == .checking
    }

    /// A Boolean value that indicates whether the Unlock button shows its own
    /// spinner: on iOS while unlocking. On macOS, the spinner sits to the
    /// right of the buttons instead.
    var showsButtonSpinner: Bool {
        #if os(iOS)
        isUnlocking
        #else
        false
        #endif
    }

    /// Clears the field and unlocks with the entered password.
    func unlock() {
        guard !password.isEmpty else { return }
        let entered = password
        password = ""
        Task { await session.unlock(masterPassword: entered, prefetchingInto: vaultModel) }
    }
}
