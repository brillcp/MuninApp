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
            VStack(alignment: .leading, spacing: 20) {
                Text("Your accounts are end-to-end encrypted with this key. Munin can't read them, and can't recover them for you.")
                Text("iCloud Keychain syncs the key to your other Apple devices. Save a copy in your password manager too: without it, losing your devices means losing your accounts.")
                    .foregroundStyle(.secondary)

                Text(recoveryKey)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                Button(didCopy ? "Copied" : "Copy Recovery Key", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
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
            .navigationTitle("Recovery Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }
}
