import SwiftUI

/// A view that restores the vault from the recovery key.
///
/// Shown when the account has vault data but the device has no vault key and
/// no master password is set.
struct MissingKeyView: View {
    @State private var recoveryKey = ""
    /// A Boolean value that indicates whether the last restore attempt used an
    /// invalid key.
    @State private var didFail = false

    /// Restores the vault from a recovery key, returning `false` if the key is
    /// invalid.
    let onRestore: (String) -> Bool
    /// Checks the server for the vault again.
    let onRetry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("vaultKey.missing.title", systemImage: DesignKit.Icon.missingKey)
        } description: {
            Text("vaultKey.missing.message")
        } actions: {
            VStack(spacing: DesignKit.Spacing.Primitive.s12) {
                TextField("vaultKey.missing.placeholder", text: $recoveryKey, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .frame(maxWidth: 360)
                if didFail {
                    Text("vaultKey.missing.invalid")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("vaultKey.missing.checkAgain") { Task { await onRetry() } }
                    Button("vaultKey.missing.restore") { didFail = !onRestore(recoveryKey) }
                        .buttonStyle(.borderedProminent)
                        .disabled(recoveryKey.isEmpty)
                }
            }
        }
    }
}
