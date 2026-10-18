import SwiftUI

/// Every field of the selected password item.
/// The password stays hidden until Show; the note is decrypted while the item is selected.
struct PasswordInspector: View {
    let item: PasswordItem
    /// Decrypts a ciphertext for the given field ("password" or "note").
    let decrypt: (_ ciphertext: String, _ field: String) throws -> String
    let onCopyPassword: () -> Void
    let onEdit: () -> Void

    @State private var revealedPassword: String?
    @State private var note: String?

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    Spacer()
                    Button("global.edit", action: onEdit)
                }
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
