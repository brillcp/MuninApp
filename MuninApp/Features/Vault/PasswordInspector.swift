import SwiftUI

/// Every field of the selected password item (the vault's detail column).
/// The password stays hidden until Show; the note is decrypted while the item is selected.
struct PasswordInspector: View {
    let item: PasswordItem
    /// Decrypts a ciphertext for the given field ("password" or "note").
    let decrypt: (_ ciphertext: String, _ field: String) throws -> String
    let onCopyPassword: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var revealedPassword: String?
    @State private var note: String?

    var body: some View {
        Form {
            // Website icon at the top. On the Mac the name sits under it (there's no
            // navigation bar); on iOS the name is the navigation title.
            Section {
                VStack(spacing: 12) {
                    WebsiteIcon(url: item.url, size: 64)
                    #if os(macOS)
                    Text(item.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    #endif
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("password.field.url") {
                    Text(item.url).textSelection(.enabled)
                }
                LabeledContent("password.field.username") {
                    Text(item.username).textSelection(.enabled)
                }
            }

            Section("password.field.password") {
                HStack {
                    Text(revealedPassword ?? "••••••••")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button(LocalizedStringKey(revealedPassword == nil ? "passwordInspector.show" : "passwordInspector.hide"),
                           systemImage: revealedPassword == nil ? "eye" : "eye.slash") {
                        if revealedPassword == nil {
                            revealedPassword = try? decrypt(item.encryptedPassword, "password")
                        } else {
                            revealedPassword = nil
                        }
                    }
                    .labelStyle(.iconOnly)
                    Button("global.copy", systemImage: "doc.on.doc", action: onCopyPassword)
                        .labelStyle(.iconOnly)
                }
            }

            Section("password.field.note") {
                Text(note ?? "")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("password.field.lastUpdated") {
                    Text(item.lastUpdated, format: .dateTime)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(item.name)
        .barkNavigationBar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("global.edit", systemImage: "square.and.pencil", action: onEdit)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("global.delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .task(id: item.id) {
            revealedPassword = nil
            note = try? decrypt(item.encryptedNote, "note")
        }
        .onDisappear {
            revealedPassword = nil
            note = nil
        }
    }
}
