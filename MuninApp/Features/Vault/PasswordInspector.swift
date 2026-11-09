import SwiftUI

/// A view that shows every field of a password item.
///
/// The password stays encrypted until it's revealed or copied; the note is
/// decrypted while the item is displayed. Tapping a row copies its value. On
/// iOS, the background and tint use the website icon's dominant color.
struct PasswordInspector: View {
    @Environment(\.openURL) private var openURL
    /// The subscription state; Delete is disabled while the vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions

    /// The decrypted password while it's revealed.
    @State private var revealedPassword: String?
    /// The decrypted note while the item is displayed.
    @State private var note: String?
    /// A counter that triggers a light haptic when incremented.
    @State private var hapticTaps = 0
    /// The website icon's dominant color, used to tint the background.
    @State private var tint: Color?
    /// The most recently copied field, which briefly shows a “Copied” label.
    @State private var copiedField: Field?
    /// The opacity of tinted row backgrounds.
    private var rowOpacity: CGFloat = 0.05

    /// The item to display.
    let item: PasswordItem
    /// Decrypts a ciphertext for the given field, `password` or `note`.
    let decrypt: (_ ciphertext: String, _ field: PasswordField) throws -> String
    /// Decrypts and copies the password.
    let onCopyPassword: () -> Void
    /// Requests deletion of the item, typically after confirmation.
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
                .padding(.vertical, DesignKit.Spacing.Primitive.s8)
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
                    Button(revealedPassword == nil ? "passwordInspector.show" : "passwordInspector.hide",
                           systemImage: revealedPassword == nil ? DesignKit.Icon.showPassword : DesignKit.Icon.hidePassword) {
                        hapticTaps += 1
                        if revealedPassword == nil {
                            revealedPassword = try? decrypt(item.encryptedPassword, .password)
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
                        Button("passwordInspector.openWebsite", systemImage: DesignKit.Icon.openWebsite) {
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
                            .textSelection(.enabled)
                    } actions: {
                        copyButton(.note) { Pasteboard.copy(note) }
                    }
                }
            }

            Section {
                LabeledContent("password.field.lastUpdated") {
                    Text(item.lastUpdated, format: .dateTime)
                }
            }

            Section {
                Button("global.delete", systemImage: DesignKit.Icon.delete, role: .destructive) {
                    hapticTaps += 1
                    onDelete()
                }
                .foregroundStyle(.red)
                .tint(.red)
                .disabled(subscriptions.isReadOnly)
            }
        }
        .frame(maxHeight: .infinity)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .animation(DesignKit.Motion.easeInOut, value: tint)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        #if os(iOS)
        .background {
            if let tint {
                tint
                    .opacity(0.12)
                    .ignoresSafeArea()
            } else {
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .task(id: item.url) {
            tint = await WebsiteIconStore.shared.dominantColor(for: item.url)
        }
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: item.encryptedNote, loadNote)
        .onChange(of: item.encryptedPassword, hidePassword)
        .onDisappear(perform: clearDecrypted)
        .tint(tint ?? .accent)
    }
}

private extension PasswordInspector {
    /// A field that can be copied.
    enum Field { case url, username, password, note }

    /// Decrypts the note, and again whenever an edit changes it.
    func loadNote() async {
        note = try? decrypt(item.encryptedNote, .note)
    }

    /// Hides a revealed password once an edit changes it.
    func hidePassword() {
        revealedPassword = nil
    }

    /// Drops the decrypted password and note when the inspector goes away.
    func clearDecrypted() {
        revealedPassword = nil
        note = nil
    }

    /// The item's website URL, using HTTPS when no scheme is given.
    var websiteURL: URL? {
        let trimmed = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }

    func copyButton(_ field: Field, perform: @escaping () -> Void) -> some View {
        Button("global.copy", systemImage: DesignKit.Icon.copy) {
            copy(field, perform: perform)
        }
    }

    /// Performs a copy and briefly shows “Copied” on the field's row.
    func copy(_ field: Field, perform: () -> Void) {
        perform()
        hapticTaps += 1
        withAnimation(DesignKit.Motion.linear) { copiedField = field }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedField == field {
                withAnimation(DesignKit.Motion.linear) { copiedField = nil }
            }
        }
    }
}
