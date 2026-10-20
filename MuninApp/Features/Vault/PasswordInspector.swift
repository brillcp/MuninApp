import SwiftUI

/// Every field of the selected password item (the vault's detail).
///
/// The password stays encrypted until it's shown or copied; the note is
/// decrypted while the item is selected. Tapping a row copies its value. On
/// iOS the background and tint use the website icon's dominant colour.
struct PasswordInspector: View {
    @Environment(\.openURL) private var openURL

    /// The decrypted password while it's shown.
    @State private var revealedPassword: String?
    /// The decrypted note while the item is shown.
    @State private var note: String?
    /// Bumped by buttons for a light haptic.
    @State private var hapticTaps = 0
    /// The website icon's dominant colour; tints the background.
    @State private var tint: Color?
    /// The field just copied, for the short "Copied" label.
    @State private var copiedField: Field?

    /// A field that can be copied.
    private enum Field { case url, username, password, note }

    /// The item's website; "kattmat.com" opens as https.
    private var websiteURL: URL? {
        let trimmed = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }

    /// Opacity for tinted row backgrounds.
    private var rowOpacity: CGFloat = 0.05

    /// The item to show.
    let item: PasswordItem
    /// Decrypts a ciphertext for the given field ("password" or "note").
    let decrypt: (_ ciphertext: String, _ field: String) throws -> String
    /// Decrypts and copies the password.
    let onCopyPassword: () -> Void
    /// Asks for confirmation; the button sits at the bottom of the list.
    let onDelete: () -> Void

    var body: some View {
        Form {
            Section {
                VStack(spacing: DesignKit.Spacing.Primitive.s16) {
                    WebsiteIcon(url: item.url, size: DesignKit.Spacing.Primitive.s72)
                    Text(item.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                DetailRow(label: "password.field.username", isCopied: copiedField == .username) {
                    Text(item.username)
                } actions: {
                    copyButton(.username) { Pasteboard.copy(item.username) }
                }
                .onTapGesture { copy(.username) { Pasteboard.copy(item.username) } }

                DetailRow(label: "password.field.password", isCopied: copiedField == .password) {
                    Text(revealedPassword ?? "••••••••••••")
                        .font(.body.monospaced())
                } actions: {
                    Button(LocalizedStringKey(revealedPassword == nil ? "passwordInspector.show" : "passwordInspector.hide"),
                           systemImage: revealedPassword == nil ? "eye" : "eye.slash") {
                        hapticTaps += 1
                        if revealedPassword == nil {
                            revealedPassword = try? decrypt(item.encryptedPassword, "password")
                        } else {
                            revealedPassword = nil
                        }
                    }
                    copyButton(.password, perform: onCopyPassword)
                }
                .onTapGesture { copy(.password, perform: onCopyPassword) }

                DetailRow(label: "password.field.url", isCopied: copiedField == .url) {
                    Text(item.url)
                } actions: {
                    if let websiteURL {
                        Button("passwordInspector.openWebsite", systemImage: "arrow.up.right.square.fill") {
                            hapticTaps += 1
                            openURL(websiteURL)
                        }
                    }
                }
                .onTapGesture { copy(.url) { Pasteboard.copy(item.url) } }
            }

            if let note, !note.isEmpty {
                Section {
                    DetailRow(label: "password.field.note", isCopied: copiedField == .note) {
                        Text(note)
                    } actions: {
                        EmptyView()
                    }
                    .onTapGesture { copy(.note) { Pasteboard.copy(note) } }
                }
            }

            Section {
                LabeledContent("password.field.lastUpdated") {
                    Text(item.lastUpdated, format: .dateTime)
                }
            }

            Section {
                Button("global.delete", systemImage: "trash", role: .destructive) {
                    hapticTaps += 1
                    onDelete()
                }
                .foregroundStyle(.red)
                .tint(.red)
            }
        }
        .frame(maxHeight: .infinity)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background {
            #if os(iOS)
            tint?
                .opacity(0.12)
                .ignoresSafeArea()
            #endif
        }
        .animation(.easeInOut, value: tint)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        #if os(iOS)
        .task(id: item.url) {
            tint = await WebsiteIconStore.shared.dominantColor(for: item.url)
        }
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: item.id) {
            revealedPassword = nil
            note = try? decrypt(item.encryptedNote, "note")
        }
        .onDisappear {
            revealedPassword = nil
            note = nil
        }
        .tint(tint ?? .accent)
    }

    /// An icon button that copies a field.
    private func copyButton(_ field: Field, perform: @escaping () -> Void) -> some View {
        Button("global.copy", systemImage: "square.on.square") {
            copy(field, perform: perform)
        }
    }

    /// Runs the copy and shows "Copied" on that row for a moment.
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

/// A field: its label small above the value, with icon buttons on the
/// trailing side. Tapping the row copies (set by the caller); the value
/// briefly reads "Copied".
private struct DetailRow<Value: View, Actions: View>: View {
    /// The field's name.
    let label: LocalizedStringKey
    /// Shows "Copied" in place of the value.
    let isCopied: Bool
    /// The field's value.
    @ViewBuilder let value: Value
    /// Icon buttons on the trailing side.
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s16) {
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Group {
                    if isCopied {
                        Text("global.copied")
                            .foregroundStyle(.tint)
                    } else {
                        value
                    }
                }
                .transition(.blurReplace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignKit.Spacing.Primitive.s16) {
                actions
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .imageScale(.large)
        }
        .padding(.vertical, DesignKit.Spacing.Primitive.s4)
        .contentShape(.rect)
    }
}
