import SwiftUI

/// Every field of the selected password item (the vault's detail column).
/// The password stays hidden until Show; the note is decrypted while the item is selected.
struct PasswordInspector: View {
    let item: PasswordItem
    /// Decrypts a ciphertext for the given field ("password" or "note").
    let decrypt: (_ ciphertext: String, _ field: String) throws -> String
    let onCopyPassword: () -> Void

    @State private var revealedPassword: String?
    @State private var note: String?
    @State private var hapticTaps = 0
    /// The field just copied, for the short "Copied" label.
    @State private var copiedField: Field?

    private enum Field { case url, username, password, note }
    @Environment(\.openURL) private var openURL

    /// The item's website; "kattmat.com" opens as https.
    private var websiteURL: URL? {
        let trimmed = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }

    var body: some View {
        Form {
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
                CopyableRow(label: "password.field.url", isCopied: copiedField == .url) {
                    copy(.url) { Pasteboard.copy(item.url) }
                } value: {
                    HStack {
                        Text(item.url)
                        if let websiteURL {
                            Button("passwordInspector.openWebsite", systemImage: "arrow.up.right.square.fill") {
                                hapticTaps += 1
                                openURL(websiteURL)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                CopyableRow(label: "password.field.username", isCopied: copiedField == .username) {
                    copy(.username) { Pasteboard.copy(item.username) }
                } value: {
                    Text(item.username)
                }
            }

            Section("password.field.password") {
                HStack {
                    Group {
                        if copiedField == .password {
                            Text("global.copied")
                                .foregroundStyle(.tint)
                        } else {
                            Text(revealedPassword ?? "••••••••")
                                .font(.body.monospaced())
                        }
                    }
                    Spacer()
                    Button(LocalizedStringKey(revealedPassword == nil ? "passwordInspector.show" : "passwordInspector.hide"),
                           systemImage: revealedPassword == nil ? "eye" : "eye.slash") {
                        hapticTaps += 1
                        if revealedPassword == nil {
                            revealedPassword = try? decrypt(item.encryptedPassword, "password")
                        } else {
                            revealedPassword = nil
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
                .contentShape(Rectangle())
                .onTapGesture { copy(.password, perform: onCopyPassword) }
            }

            // Only when the item has a note.
            if let note, !note.isEmpty {
                Section("password.field.note") {
                    Group {
                        if copiedField == .note {
                            Text("global.copied")
                                .foregroundStyle(.tint)
                        } else {
                            Text(note)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { copy(.note) { Pasteboard.copy(note) } }
                }
            }

            Section {
                LabeledContent("password.field.lastUpdated") {
                    Text(item.lastUpdated, format: .dateTime)
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        // Lets the glass panel show through behind the sections.
        .scrollContentBackground(.hidden)
        #endif
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        #if os(iOS)
        // Mac: the name is under the icon instead. As a window title its
        // changing width moved the toolbar buttons with every selection.
        .navigationTitle(item.name)
        #endif
        .barkNavigationBar()
        .task(id: item.id) {
            revealedPassword = nil
            note = try? decrypt(item.encryptedNote, "note")
        }
        .onDisappear {
            revealedPassword = nil
            note = nil
        }
    }

    private func copy(_ field: Field, perform: () -> Void) {
        perform()
        hapticTaps += 1
        withAnimation { copiedField = field }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedField == field {
                withAnimation { copiedField = nil }
            }
        }
    }
}

/// A labeled row that copies its value when tapped, showing "Copied" briefly.
private struct CopyableRow<Value: View>: View {
    let label: LocalizedStringKey
    let isCopied: Bool
    let onCopy: () -> Void
    @ViewBuilder let value: Value

    var body: some View {
        LabeledContent(label) {
            if isCopied {
                Text("global.copied")
                    .foregroundStyle(.tint)
            } else {
                value
            }
        }
        .contentShape(.rect)
        .transition(.blurReplace)
        .onTapGesture(perform: onCopy)
    }
}
