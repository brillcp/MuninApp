import SwiftUI

/// Shown when Munin has data but this device has no vault key for it.
struct MissingKeyView: View {
    let onRestore: (String) -> Bool
    let onRetry: () async -> Void

    @State private var recoveryKey = ""
    @State private var didFail = false

    var body: some View {
        ContentUnavailableView {
            Label("Vault key not on this device", systemImage: "key.slash")
        } description: {
            Text("Your vault is encrypted with a key from your other device. Turn on iCloud Keychain on both devices and check again, or paste your recovery key.")
        } actions: {
            VStack(spacing: 12) {
                TextField("Recovery key", text: $recoveryKey, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .frame(maxWidth: 360)
                if didFail {
                    Text("That isn't a valid recovery key.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Check Again") { Task { await onRetry() } }
                    Button("Restore") { didFail = !onRestore(recoveryKey) }
                        .buttonStyle(.borderedProminent)
                        .disabled(recoveryKey.isEmpty)
                }
            }
        }
    }
}
