import SwiftUI

/// A step that accepts the recovery key so the user can set a new master
/// password.
///
/// On success, ``VaultSession`` moves to master password setup. The step is
/// only reachable from the forgot-password action, so the field is focused on
/// appear.
struct LockRecoveryKeyStep: View {
    /// The vault session to unlock.
    @Environment(VaultSession.self) private var session
    /// The recovery key the user entered.
    @State private var recoveryKey = ""
    /// A Boolean value that indicates whether the recovery key field has focus.
    @FocusState private var isFieldFocused: Bool

    /// The action that returns to the previous step.
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
            Text("lock.recovery.message")
                .foregroundStyle(.secondary)
            TextField("lock.recovery.placeholder", text: $recoveryKey, axis: .vertical)
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
