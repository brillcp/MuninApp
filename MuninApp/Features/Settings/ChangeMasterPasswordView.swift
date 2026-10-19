import SwiftUI

/// Current password, then the new one twice. The vault key itself doesn't
/// change; it's wrapped again with the new password.
struct ChangeMasterPasswordView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var password = ""
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
                    Button("global.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if session.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("global.save", action: save)
                            .disabled(!isValid)
                    }
                }
            }
        }
        .onAppear { session.clearError() }
        .onDisappear { session.clearError() }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private var isValid: Bool {
        !current.isEmpty && password.count >= VaultSession.minimumPasswordLength && password == confirmation
    }

    private var problem: LocalizedStringKey? {
        if !password.isEmpty, password.count < VaultSession.minimumPasswordLength {
            return LocalizedKey("masterPassword.tooShort", VaultSession.minimumPasswordLength)
        }
        if !confirmation.isEmpty, password != confirmation {
            return "masterPassword.mismatch"
        }
        return nil
    }

    private func save() {
        guard isValid else { return }
        Task {
            if await session.changeMasterPassword(current: current, new: password, auth: auth) {
                dismiss()
            }
        }
    }
}
