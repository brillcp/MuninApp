import SwiftUI

/// A view that shows every field of a stored card.
///
/// The number and security code stay encrypted until they're revealed or
/// copied, each in its own ``CardSecretRow``; the expiry date and note are
/// decrypted while the card is displayed. Tapping a row copies its value,
/// except a revealed number or code, so it can be selected instead. Copied
/// numbers and codes are cleared from the clipboard after a minute.
struct CardInspector: View {
    /// The subscription state; Delete is disabled while the vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions

    /// The decrypted expiry date while the card is displayed.
    @State private var expiry: String?
    /// The decrypted note while the card is displayed.
    @State private var note: String?
    /// A counter that triggers a light haptic when incremented.
    @State private var hapticTaps = 0
    /// The most recently copied field, which briefly shows a “Copied” label.
    @State private var copiedField: CardField?

    /// The card to display.
    let item: CardItem
    /// Decrypts a ciphertext for the given field.
    let decrypt: (_ ciphertext: String, _ field: CardField) throws -> String
    /// Decrypts and copies the number or security code, clearing it from the
    /// clipboard after a minute.
    let onCopySensitive: (_ ciphertext: String, _ field: CardField) -> Void
    /// Requests deletion of the card, typically after confirmation.
    let onDelete: () -> Void

    var body: some View {
        Form {
            CardInspectorHeader(name: item.name)

            Section {
                if !item.holder.isEmpty {
                    DetailRow(label: "card.field.holder", isCopied: copiedField == .holder) {
                        Text(item.holder)
                    } actions: {
                        copyButton(.holder, perform: copyHolder)
                    }
                    .onTapGesture { copy(.holder, perform: copyHolder) }
                }

                CardSecretRow(
                    label: "card.field.number",
                    maskedValue: "•••• \(item.lastDigits)",
                    ciphertext: item.encryptedNumber,
                    field: .number,
                    isCopied: copiedField == .number,
                    decrypt: decrypt,
                    onCopy: copyNumberWithFeedback
                )

                if let expiry, !expiry.isEmpty {
                    DetailRow(label: "card.field.expiry", isCopied: copiedField == .expiry) {
                        Text(expiry)
                            .font(.body.monospaced())
                    } actions: {
                        copyButton(.expiry, perform: copyExpiry)
                    }
                    .onTapGesture { copy(.expiry, perform: copyExpiry) }
                }

                CardSecretRow(
                    label: "card.field.cvv",
                    maskedValue: "•••",
                    ciphertext: item.encryptedCVV,
                    field: .cvv,
                    isCopied: copiedField == .cvv,
                    decrypt: decrypt,
                    onCopy: copyCVVWithFeedback
                )
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
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        #if os(iOS)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: item.encryptedExpiry, loadExpiry)
        .task(id: item.encryptedNote, loadNote)
        .onDisappear(perform: clearDecrypted)
    }
}

private extension CardInspector {
    /// Decrypts the expiry date, and again whenever an edit changes it.
    func loadExpiry() async {
        expiry = try? decrypt(item.encryptedExpiry, .expiry)
    }

    /// Decrypts the note, and again whenever an edit changes it.
    func loadNote() async {
        note = try? decrypt(item.encryptedNote, .note)
    }

    /// Drops the decrypted expiry date and note when the inspector goes away.
    ///
    /// Each ``CardSecretRow`` drops its own revealed value.
    func clearDecrypted() {
        expiry = nil
        note = nil
    }

    /// Copies the cardholder name.
    func copyHolder() {
        Pasteboard.copy(item.holder)
    }

    /// Copies the card number, cleared from the clipboard after a minute.
    func copyNumber() {
        onCopySensitive(item.encryptedNumber, .number)
    }

    /// Copies the expiry date.
    func copyExpiry() {
        if let expiry { Pasteboard.copy(expiry) }
    }

    /// Copies the security code, cleared from the clipboard after a minute.
    func copyCVV() {
        onCopySensitive(item.encryptedCVV, .cvv)
    }

    /// Copies the number and briefly shows “Copied” on its row.
    func copyNumberWithFeedback() {
        copy(.number, perform: copyNumber)
    }

    /// Copies the security code and briefly shows “Copied” on its row.
    func copyCVVWithFeedback() {
        copy(.cvv, perform: copyCVV)
    }

    /// A Copy button for a field's row.
    ///
    /// - Parameters:
    ///   - field: The field the button copies, which shows “Copied” afterward.
    ///   - perform: The action that copies the field's value.
    func copyButton(_ field: CardField, perform: @escaping () -> Void) -> some View {
        Button("global.copy", systemImage: DesignKit.Icon.copy) {
            copy(field, perform: perform)
        }
    }

    /// Performs a copy and briefly shows “Copied” on the field's row.
    func copy(_ field: CardField, perform: () -> Void) {
        perform()
        hapticTaps += 1
        withAnimation(DesignKit.Motion.linear) { copiedField = field }
        Task {
            try? await Task.sleep(for: DesignKit.Motion.copiedFeedback)
            if copiedField == field {
                withAnimation(DesignKit.Motion.linear) { copiedField = nil }
            }
        }
    }
}
