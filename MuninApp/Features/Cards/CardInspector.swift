import SwiftUI

/// A view that shows every field of a stored card.
///
/// The number and security code stay encrypted until they're revealed or
/// copied; the expiry date and note are decrypted while the card is
/// displayed. Tapping a row copies its value, except a revealed number or
/// code, so it can be selected instead. Copied numbers and codes are cleared
/// from the clipboard after a minute.
struct CardInspector: View {
    /// The subscription state; Delete is disabled while the vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions

    /// The decrypted card number while it's revealed.
    @State private var revealedNumber: String?
    /// The decrypted security code while it's revealed.
    @State private var revealedCVV: String?
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
            Section {
                VStack(spacing: DesignKit.Spacing.Primitive.s16) {
                    Image(systemName: DesignKit.Icon.cards)
                        .font(.system(size: DesignKit.Spacing.Primitive.s48))
                        .foregroundStyle(.tint)
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
                if !item.holder.isEmpty {
                    DetailRow(label: "card.field.holder", isCopied: copiedField == .holder) {
                        Text(item.holder)
                    } actions: {
                        copyButton(.holder, perform: copyHolder)
                    }
                    .onTapGesture { copy(.holder, perform: copyHolder) }
                }

                DetailRow(label: "card.field.number", isCopied: copiedField == .number) {
                    if let revealedNumber {
                        Text(verbatim: CardItem.formatted(revealedNumber))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    } else {
                        Text(verbatim: "•••• \(item.lastDigits)")
                            .font(.body.monospaced())
                    }
                } actions: {
                    revealButton(isRevealed: revealedNumber != nil, action: toggleNumber)
                    copyButton(.number, perform: copyNumber)
                }
                .gesture(TapGesture().onEnded(copyNumberFromRow), isEnabled: revealedNumber == nil)

                if let expiry, !expiry.isEmpty {
                    DetailRow(label: "card.field.expiry", isCopied: copiedField == .expiry) {
                        Text(expiry)
                            .font(.body.monospaced())
                    } actions: {
                        copyButton(.expiry, perform: copyExpiry)
                    }
                    .onTapGesture { copy(.expiry, perform: copyExpiry) }
                }

                DetailRow(label: "card.field.cvv", isCopied: copiedField == .cvv) {
                    if let revealedCVV {
                        Text(revealedCVV)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    } else {
                        Text(verbatim: "•••")
                            .font(.body.monospaced())
                    }
                } actions: {
                    revealButton(isRevealed: revealedCVV != nil, action: toggleCVV)
                    copyButton(.cvv, perform: copyCVV)
                }
                .gesture(TapGesture().onEnded(copyCVVFromRow), isEnabled: revealedCVV == nil)
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
        .onChange(of: item.encryptedNumber, hideNumber)
        .onChange(of: item.encryptedCVV, hideCVV)
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

    /// Hides a revealed number once an edit changes it.
    func hideNumber() {
        revealedNumber = nil
    }

    /// Hides a revealed security code once an edit changes it.
    func hideCVV() {
        revealedCVV = nil
    }

    /// Drops every decrypted value when the inspector goes away.
    func clearDecrypted() {
        revealedNumber = nil
        revealedCVV = nil
        expiry = nil
        note = nil
    }

    /// Reveals or hides the card number.
    func toggleNumber() {
        hapticTaps += 1
        revealedNumber = revealedNumber == nil ? try? decrypt(item.encryptedNumber, .number) : nil
    }

    /// Reveals or hides the security code.
    func toggleCVV() {
        hapticTaps += 1
        revealedCVV = revealedCVV == nil ? try? decrypt(item.encryptedCVV, .cvv) : nil
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

    /// Copies the number from a tap on its row while it's hidden.
    func copyNumberFromRow() {
        copy(.number, perform: copyNumber)
    }

    /// Copies the security code from a tap on its row while it's hidden.
    func copyCVVFromRow() {
        copy(.cvv, perform: copyCVV)
    }

    /// A Show or Hide button for a hidden field's row.
    ///
    /// - Parameters:
    ///   - isRevealed: Whether the field is revealed.
    ///   - action: The action that reveals or hides the field.
    func revealButton(isRevealed: Bool, action: @escaping () -> Void) -> some View {
        Button(isRevealed ? "passwordInspector.hide" : "passwordInspector.show",
               systemImage: isRevealed ? DesignKit.Icon.hidePassword : DesignKit.Icon.showPassword,
               action: action)
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
