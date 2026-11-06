import SwiftUI

/// A view that changes the master password.
///
/// The user enters the current password, then the new one twice. The vault
/// key doesn't change; it's rewrapped with the new password.
struct ChangeMasterPasswordView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// The current master password.
    @State private var current = ""
    /// The new master password.
    @State private var password = ""
    /// The new master password, typed again.
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("settings.currentMasterPassword", text: $current)
                        #if os(iOS)
                        .textContentType(.password)
                        #endif
                }
                Section {
                    SecureField("masterPassword.field", text: $password)
                        #if os(iOS)
                        .textContentType(.newPassword)
                        #endif
                    SecureField("masterPassword.confirm", text: $confirmation)
                        #if os(iOS)
                        .textContentType(.newPassword)
                        #endif
                        .onSubmit(save)
                } footer: {
                    if let problem {
                        Text(problem)
                    }
                }
                if let error = session.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .disabled(session.isWorking)
            .navigationTitle("settings.changeMasterPassword")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("global.cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if session.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.primary)
                    } else {
                        Button("global.save", action: save)
                            .disabled(!isValid)
                    }
                }
            }
        }
        .onAppear(perform: session.clearError)
        .onDisappear(perform: session.clearError)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }
}

private extension ChangeMasterPasswordView {
    /// A Boolean value that indicates whether Save is enabled.
    ///
    /// Requires the current password and a matching new password of sufficient length.
    var isValid: Bool {
        !current.isEmpty && password.count >= VaultSession.minimumPasswordLength && password == confirmation
    }

    /// The validation message shown below the new password fields, if any.
    var problem: LocalizedStringKey? {
        if !password.isEmpty, password.count < VaultSession.minimumPasswordLength {
            return LocalizedKey("masterPassword.tooShort", VaultSession.minimumPasswordLength)
        }
        if !confirmation.isEmpty, password != confirmation {
            return "masterPassword.mismatch"
        }
        return nil
    }

    /// Changes the master password and closes the sheet on success.
    func save() {
        guard isValid else { return }
        Task {
            if await session.changeMasterPassword(current: current, new: password, auth: auth) {
                dismiss()
            }
        }
    }
}
