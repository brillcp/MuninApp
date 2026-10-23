import SwiftUI

/// Sheet for creating a password item, or editing one when `isEditing` is true.
///
/// Each field is encrypted before it's sent. The sections match the detail
/// view (`PasswordInspector`). A new item starts with the name field focused;
/// editing doesn't move focus.
struct PasswordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    /// The fields being edited, in plain text while the sheet is open.
    @State private var fields: PasswordFields
    /// True while saving.
    @State private var isSaving = false
    /// Shows the password generator popover.
    @State private var isGenerating = false
    /// The last save error.
    @State private var errorMessage: String?
    /// Bumped by buttons for a light haptic.
    @State private var hapticTaps = 0
    /// Whether the name field has keyboard focus.
    @FocusState private var isNameFocused: Bool

    /// Editing an existing item rather than creating one.
    let isEditing: Bool
    /// Encrypts and saves the fields. A thrown error is shown in the sheet.
    let onSave: (PasswordFields) async throws -> Void

    /// Creates the editor, prefilled with `fields` when editing.
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
                        Button("passwordEditor.generate", systemImage: "wand.and.stars") {
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
            .navigationTitle(LocalizedStringKey(isEditing ? "passwordEditor.editTitle" : "passwordEditor.newTitle"))
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
    /// Saves the fields and closes the sheet, or shows the error.
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

#Preview {
    PasswordEditorView { _ in }
}
