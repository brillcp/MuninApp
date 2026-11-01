import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Shows the recovery key so the user can store it somewhere safe.
///
/// The recovery key resets a forgotten master password.
struct RecoveryKeyView: View {
    @Environment(\.dismiss) private var dismiss
    /// Set after copying, to show "Copied" on the button.
    @State private var didCopy = false

    /// The recovery key, formatted in groups of four characters.
    let recoveryKey: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
                Text("vaultKey.recovery.explanation")
                Text("vaultKey.recovery.backup")
                    .foregroundStyle(.secondary)

                Text(recoveryKey)
                    .font(.system(.body, design: .monospaced, weight: .regular))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignKit.Spacing.Primitive.s12))

                Button(didCopy ? "global.copied" : "vaultKey.recovery.copy", systemImage: didCopy ? DesignKit.Icon.copied : DesignKit.Icon.copy) {
                    #if os(iOS)
                    UIPasteboard.general.string = recoveryKey
                    #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recoveryKey, forType: .string)
                    #endif
                    didCopy = true
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .navigationTitle("vaultKey.recovery.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("global.done", action: dismiss.callAsFunction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }
}
