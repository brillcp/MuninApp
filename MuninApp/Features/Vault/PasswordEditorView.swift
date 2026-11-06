import SwiftUI

/// A sheet for creating or editing a password item.
///
/// Fields are encrypted before they're sent. The sections match
/// ``PasswordInspector``. When creating an item, the name field starts with
/// focus.
struct PasswordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    /// The fields being edited, in plain text while the sheet is open.
    @State private var fields: PasswordFields
    @State private var isSaving = false
    /// A Boolean value that indicates whether the password generator popover is shown.
    @State private var isGenerating = false
    /// The most recent save error.
    @State private var errorMessage: String?
    /// A counter that triggers a light haptic when incremented.
    @State private var hapticTaps = 0
    @FocusState private var isNameFocused: Bool

    /// A Boolean value that indicates whether an existing item is being edited.
    let isEditing: Bool
    /// Encrypts and saves the fields; a thrown error is shown in the sheet.
    let onSave: (PasswordFields) async throws -> Void

    /// Creates a password editor.
    ///
    /// - Parameters:
    ///   - fields: The initial field values.
    ///   - isEditing: Whether an existing item is being edited.
    ///   - onSave: Encrypts and saves the fields.
    init(fields: PasswordFields = PasswordFields(), isEditing: Bool = false, onSave: @escaping (PasswordFields) async throws -> Void) {
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
                    TextField("password.field.url", text: $fields.url)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("password.field.username", text: $fields.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }

                Section("password.field.password") {
                    HStack {
                        SecureField("password.field.password", text: $fields.password)
                        Button("passwordEditor.generate", systemImage: DesignKit.Icon.generatePassword) {
                            hapticTaps += 1
                            isGenerating = true
                        }
                        .labelStyle(.iconOnly)
                        .popover(isPresented: $isGenerating) {
                            PasswordGeneratorView { generated in
                                fields.password = generated
                                isGenerating = false
                            }
                        }
                    }
                }

                Section("password.field.note") {
                    TextField("password.field.note", text: $fields.note, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { isNameFocused = !isEditing }
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
            .disabled(isSaving)
            .navigationTitle(isEditing ? "passwordEditor.editTitle" : "passwordEditor.newTitle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("global.cancel") {
                        hapticTaps += 1
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("global.save") {
                        hapticTaps += 1
                        save()
                    }
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

private extension PasswordEditorView {
    /// Saves the fields and dismisses the sheet, or shows the error.
    func save() {
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
