import SwiftUI

/// A view that shows the recovery key so the user can store it safely.
///
/// The recovery key resets a forgotten master password. The content scrolls,
/// so nothing is cut off on small screens or with large text.
struct RecoveryKeyView: View {
    /// The action that closes the view.
    @Environment(\.dismiss) private var dismiss
    /// A Boolean value that indicates whether the key was copied, which
    /// changes the button to “Copied”.
    @State private var didCopy = false

    /// The recovery key, formatted in groups of four characters.
    let recoveryKey: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
                    Text("vaultKey.recovery.explanation")
                    Text("vaultKey.recovery.backup")
                        .foregroundStyle(.secondary)

                    Text(recoveryKey)
                        .monospaced()
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignKit.Spacing.Primitive.s12))

                    Button(didCopy ? "global.copied" : "vaultKey.recovery.copy", systemImage: didCopy ? DesignKit.Icon.copied : DesignKit.Icon.copy) {
                        Pasteboard.copy(recoveryKey)
                        didCopy = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            #if os(iOS)
            .leadingNavigationTitle("vaultKey.recovery.title")
            #else
            .navigationTitle("vaultKey.recovery.title")
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: dismiss.callAsFunction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }
}
