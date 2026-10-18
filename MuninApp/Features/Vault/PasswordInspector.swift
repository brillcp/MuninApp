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
                    Button("Edit", action: onEdit)
                }
            }

            Section {
                LabeledContent("URL") {
                    Text(item.url).textSelection(.enabled)
                }
                LabeledContent("Username") {
                    Text(item.username).textSelection(.enabled)
                }
            }

            Section("Password") {
                HStack {
                    Text(revealedPassword ?? "••••••••")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button(revealedPassword == nil ? "Show" : "Hide",
                           systemImage: revealedPassword == nil ? "eye" : "eye.slash") {
                        if revealedPassword == nil {
                            revealedPassword = try? decrypt(item.encryptedPassword, "password")
                        } else {
                            revealedPassword = nil
                        }
                    }
                    .labelStyle(.iconOnly)
                    Button("Copy", systemImage: "doc.on.doc", action: onCopyPassword)
                        .labelStyle(.iconOnly)
                }
            }

            Section("Note") {
                Text(note ?? "")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("Last Updated") {
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
