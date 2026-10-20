import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Shows the vault key so the user can store it somewhere safe.
struct RecoveryKeyView: View {
    let recoveryKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

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
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                Button(LocalizedStringKey(didCopy ? "global.copied" : "vaultKey.recovery.copy"), systemImage: didCopy ? "checkmark" : "square.on.square") {
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
                    Button("global.done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }
}
