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

    init(fields: PasswordFields = PasswordFields(), isEditing: Bool = false, onSave: @escaping (PasswordFields) async throws -> Void) {
        self.isEditing = isEditing
        self.onSave = onSave
        _fields = State(initialValue: fields)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $fields.name)
                TextField("URL", text: $fields.url)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Username", text: $fields.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                HStack {
                    SecureField("Password", text: $fields.password)
                    Button("Generate", systemImage: "wand.and.stars") { isGenerating = true }
                        .labelStyle(.iconOnly)
                        .popover(isPresented: $isGenerating) {
                            PasswordGeneratorView { generated in
                                fields.password = generated
                                isGenerating = false
                            }
                        }
                }
                TextField("Note", text: $fields.note, axis: .vertical)
                    .lineLimit(3...8)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .disabled(isSaving)
            .navigationTitle(isEditing ? "Edit Password" : "New Password")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
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
