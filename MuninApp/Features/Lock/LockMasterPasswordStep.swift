import SwiftUI

/// A step that unlocks with the master password, with options to use
/// biometrics or the recovery key.
struct LockMasterPasswordStep: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    /// The view model that receives the password list during unlock.
    @Environment(VaultViewModel.self) private var vaultModel
    /// The entered master password, cleared on submit.
    @State private var password = ""
    @FocusState private var isFieldFocused: Bool

    /// A Boolean value that indicates whether to focus the field on appear.
    ///
    /// True when the user chose this step instead of landing on it by default.
    let focusesField: Bool
    /// The action that switches to biometric unlock, or `nil` to hide the button.
    let onUseBiometrics: (() -> Void)?
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
                LockButton("lock.unlock", isLoading: session.isWorking || session.state == .checking, action: unlock)
                    .disabled(password.isEmpty)

                if let onUseBiometrics {
                    LockButton(
                        systemImage: session.usesFaceID ? DesignKit.Icon.faceID : DesignKit.Icon.touchID,
                        style: .secondary,
                        action: onUseBiometrics
                    )
                    .buttonSizing(.fitted)
                }
            }
            LockButton("lock.forgotMasterPassword", style: .tertiary, action: onForgotPassword)
        }
    }
}

private extension LockMasterPasswordStep {
    /// Clears the field and unlocks with the entered password.
    func unlock() {
        guard !password.isEmpty else { return }
        let entered = password
        password = ""
        Task { await session.unlock(masterPassword: entered, prefetchingInto: vaultModel, auth: auth) }
    }
}
