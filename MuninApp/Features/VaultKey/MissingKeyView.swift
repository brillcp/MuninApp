import SwiftUI

/// Shown when Munin has data but this device has no vault key for it.
struct MissingKeyView: View {
    let onRestore: (String) -> Bool
    let onRetry: () async -> Void

    @State private var recoveryKey = ""
    @State private var didFail = false

    var body: some View {
        ContentUnavailableView {
            Label("vaultKey.missing.title", systemImage: "key.slash")
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
