import SwiftUI

/// A row that shows a hidden card field, such as the number or security code,
/// with Show and Copy buttons.
///
/// The value is decrypted only while it's revealed, and hidden again when an
/// edit changes it or the row goes away. While it's hidden, tapping the row
/// copies it; while it's revealed, it can be selected instead.
struct CardSecretRow: View {
    /// The decrypted value while it's revealed.
    @State private var revealed: String?
    /// A counter that triggers a light haptic when incremented.
    @State private var hapticTaps = 0

    /// The field's name, shown above the value.
    let label: LocalizedStringKey
    /// The text shown while the value is hidden, such as `•••• 4242`.
    let maskedValue: String
    /// The encrypted value.
    let ciphertext: String
    /// The field the value belongs to.
    let field: CardField
    /// A Boolean value that indicates whether to show “Copied” in place of the value.
    let isCopied: Bool
    /// Decrypts a ciphertext for the given field.
    let decrypt: (_ ciphertext: String, _ field: CardField) throws -> String
    /// Copies the value and shows that it was copied.
    let onCopy: () -> Void

    var body: some View {
        DetailRow(label: label, isCopied: isCopied) {
            if let revealed {
                Text(verbatim: displayed(revealed))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            } else {
                Text(verbatim: maskedValue)
                    .font(.body.monospaced())
            }
        } actions: {
            Button(revealed == nil ? "passwordInspector.show" : "passwordInspector.hide",
                   systemImage: revealed == nil ? DesignKit.Icon.showPassword : DesignKit.Icon.hidePassword,
                   action: toggle)
            Button("global.copy", systemImage: DesignKit.Icon.copy, action: onCopy)
        }
        .gesture(TapGesture().onEnded(onCopy), isEnabled: revealed == nil)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        .onChange(of: ciphertext, hide)
        .onDisappear(perform: hide)
    }
}

private extension CardSecretRow {
    /// Reveals or hides the value.
    func toggle() {
        hapticTaps += 1
        revealed = revealed == nil ? try? decrypt(ciphertext, field) : nil
    }

    /// Hides a revealed value, dropping it from memory.
    func hide() {
        revealed = nil
    }

    /// Returns a revealed value as shown: a card number in groups of four
    /// digits, anything else unchanged.
    func displayed(_ value: String) -> String {
        field == .number ? CardItem.formatted(value) : value
    }
}
