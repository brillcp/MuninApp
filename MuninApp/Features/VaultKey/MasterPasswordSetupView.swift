import SwiftUI

/// A view for choosing a master password, during first setup or after unlocking with the recovery key.
struct MasterPasswordSetupView: View {
    @Environment(VaultSession.self) private var session

    /// The new master password.
    @State private var password = ""
    /// The confirmation of the new master password.
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
            Text(session.isResettingMasterPassword ? "masterPassword.reset.title" : "masterPassword.create.title")
                .font(.largeTitle.bold())
            Text("masterPassword.create.message")
                .foregroundStyle(.secondary)

            VStack(spacing: DesignKit.Spacing.Primitive.s12) {
                SecureField("masterPassword.field", text: $password)
                    #if os(iOS)
                    .textContentType(.newPassword)
                    #endif
                SecureField("masterPassword.confirm", text: $confirmation)
                    #if os(iOS)
                    .textContentType(.newPassword)
                    #endif
                    .onSubmit(save)
            }
            .textFieldStyle(.roundedBorder)

            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = session.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                if session.isResettingMasterPassword {
                    Button("global.cancel", action: session.cancelReset)
                }
                Button("global.save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || session.isWorking)
                if session.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.primary)
                }
            }
        }
        .frame(maxWidth: 420)
        .padding(DesignKit.Spacing.Primitive.s32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension MasterPasswordSetupView {
    /// A Boolean value that indicates whether the password is long enough and matches its confirmation.
    var isValid: Bool {
        password.count >= VaultSession.minimumPasswordLength && password == confirmation
    }

    /// A description of the password's problem, shown below the fields.
    var problem: LocalizedStringKey? {
        if !password.isEmpty, password.count < VaultSession.minimumPasswordLength {
            return LocalizedKey("masterPassword.tooShort", VaultSession.minimumPasswordLength)
        }
        if !confirmation.isEmpty, password != confirmation {
            return "masterPassword.mismatch"
        }
        return nil
    }

    /// Sets the master password and unlocks the vault.
    func save() {
        guard isValid else { return }
        Task { await session.setMasterPassword(password) }
    }
}
