import SwiftUI

/// A sheet for creating or editing a stored card.
///
/// Fields are encrypted before they're sent. The sections match
/// ``CardInspector``. When creating a card, the name field starts with focus.
/// The card number is grouped in fours as it's typed.
struct CardEditorView: View {
    /// The action that closes the editor.
    @Environment(\.dismiss) private var dismiss
    /// The fields being edited, in plain text while the sheet is open.
    @State private var fields: CardFields
    /// A Boolean value that indicates whether a save is in progress.
    @State private var isSaving = false
    /// The most recent save error.
    @State private var errorMessage: String?
    /// A counter that triggers a light haptic when incremented.
    @State private var hapticTaps = 0
    /// A Boolean value that indicates whether the name field has focus.
    @FocusState private var isNameFocused: Bool

    /// A Boolean value that indicates whether an existing card is being edited.
    let isEditing: Bool
    /// Encrypts and saves the fields; a thrown error is shown in the sheet.
    let onSave: (CardFields) async throws -> Void

    /// Creates a card editor.
    ///
    /// - Parameters:
    ///   - fields: The initial field values.
    ///   - isEditing: Whether an existing card is being edited.
    ///   - onSave: Encrypts and saves the fields.
    init(fields: CardFields = CardFields(), isEditing: Bool = false, onSave: @escaping (CardFields) async throws -> Void) {
        self.isEditing = isEditing
        self.onSave = onSave
        self.fields = fields
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("password.field.name", text: $fields.name)
                        .focused($isNameFocused)
                }

                Section {
                    TextField("card.field.holder", text: $fields.holder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textContentType(.creditCardName)
                        #endif
                    TextField("card.field.number", text: $fields.number)
                        .monospaced()
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        .textContentType(.creditCardNumber)
                        #endif
                    TextField("card.field.expiry", text: $fields.expiry, prompt: Text(verbatim: "MM/YY"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                    SecureField("card.field.cvv", text: $fields.cvv)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                Section("password.field.note") {
                    TextEditor(text: $fields.note)
                        .frame(minHeight: DesignKit.Spacing.Primitive.s72)
                        .scrollContentBackground(.hidden)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear(perform: focusName)
            .onChange(of: fields.number, formatNumber)
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
            .disabled(isSaving)
            #if os(iOS)
            .leadingNavigationTitle(isEditing ? "cardEditor.editTitle" : "cardEditor.newTitle", onCancel: cancel)
            #else
            .navigationTitle(isEditing ? "cardEditor.editTitle" : "cardEditor.newTitle")
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel, action: cancel)
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(fields.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }
}

private extension CardEditorView {
    /// Focuses the name field when creating a card.
    func focusName() {
        isNameFocused = !isEditing
    }

    /// Groups the card number in fours while it's typed or pasted, such as
    /// `4242 4242 4242 4242`, dropping anything that isn't a digit.
    func formatNumber() {
        let formatted = CardItem.formatted(fields.number)
        if formatted != fields.number { fields.number = formatted }
    }

    /// Closes the editor without saving.
    func cancel() {
        hapticTaps += 1
        dismiss()
    }

    /// Saves the fields and dismisses the sheet, or shows the error.
    func save() {
        hapticTaps += 1
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await onSave(fields)
                dismiss()
            } catch {
                errorMessage = error.muninDescription
            }
        }
    }
}
