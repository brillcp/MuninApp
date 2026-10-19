import SwiftUI

/// Sheet for creating a password item, or editing one when `isEditing` is true.
/// Each field is encrypted before it's sent.
struct PasswordEditorView: View {
    let isEditing: Bool
    let onSave: (PasswordFields) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fields: PasswordFields
    @State private var isSaving = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var hapticTaps = 0
    @FocusState private var isNameFocused: Bool

    init(fields: PasswordFields = PasswordFields(), isEditing: Bool = false, onSave: @escaping (PasswordFields) async throws -> Void) {
        self.isEditing = isEditing
        self.onSave = onSave
        self.fields = fields
    }

    var body: some View {
        NavigationStack {
            // Same sections as the detail view (PasswordInspector), so the two match.
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
            // A new item starts typing in the name field; editing doesn't steal focus.
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

    private func save() {
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
