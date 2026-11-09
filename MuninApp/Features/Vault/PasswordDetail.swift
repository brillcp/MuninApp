import SwiftUI

/// A view that shows a password item's details and handles editing and
/// deleting it.
///
/// On iOS, Edit (⌘E) appears in the toolbar. On macOS, the panel has its own
/// Edit button in its header. Delete asks for confirmation first. When
/// `dismissesWhenDeleted` is true, the view dismisses itself once the item is
/// gone.
struct PasswordDetail: View {
    /// The subscription state. Editing and deleting are disabled while the
    /// vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    /// The item being edited, with its password and note decrypted.
    @State private var editing: VaultViewModel.EditDraft?
    /// The item awaiting delete confirmation.
    @State private var pendingDeletion: PasswordItem?
    /// A counter incremented by Edit to trigger a light haptic.
    @State private var hapticTaps = 0

    /// The item to show, or `nil` to show nothing.
    let item: PasswordItem?
    /// The view model that decrypts, copies, edits, and deletes the item.
    let viewModel: VaultViewModel
    /// A Boolean value that indicates whether the view dismisses itself when the
    /// item is deleted.
    var dismissesWhenDeleted = false

    var body: some View {
        Group {
            if let item {
                PasswordInspector(item: item, decrypt: decrypt, onCopyPassword: copyPassword, onDelete: confirmDeletion)
                    .id(item.id)
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("global.edit", systemImage: DesignKit.Icon.edit, action: startEditing)
                    .disabled(item == nil || subscriptions.isReadOnly)
                    .keyboardShortcut("e")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        #else
        .safeAreaInset(edge: .top, spacing: DesignKit.Spacing.Primitive.s0) {
            HStack {
                LockButton(systemImage: DesignKit.Icon.close, style: .clear) {
                    hapticTaps += 1
                    viewModel.selection = nil
                }
                Spacer()
                LockButton(systemImage: DesignKit.Icon.edit, style: .clear) {
                    hapticTaps += 1
                    startEditing()
                }
                .disabled(subscriptions.isReadOnly)
                .keyboardShortcut("e")
            }
            .padding([.horizontal, .top], DesignKit.Spacing.Primitive.s12)
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .glassEffect(in: .rect(cornerRadius: DesignKit.Spacing.Primitive.s16))
        .padding(DesignKit.Spacing.Primitive.s12)
        .transition(.opacity.combined(with: .offset(x: DesignKit.Spacing.Primitive.s40)))
        #endif
        .sheet(item: $editing) { draft in
            PasswordEditorView(fields: draft.fields, isEditing: true) { fields in
                try viewModel.update(draft.item, with: fields)
            }
        }
        .confirmationDialog("vault.delete.title", item: $pendingDeletion, titleVisibility: .visible) { item in
            Button(LocalizedKey("vault.delete.button", item.name), role: .destructive) {
                viewModel.delete(item)
            }
        } message: { item in
            Text(LocalizedKey("vault.delete.message", item.name))
        }
        .onChange(of: item == nil, itemRemoved)
    }
}

private extension PasswordDetail {
    /// Decrypts one of the item's fields for the inspector.
    func decrypt(_ ciphertext: String, field: PasswordField) throws -> String {
        try viewModel.decrypt(ciphertext, field: field)
    }

    /// Copies the password and updates the item's modification date.
    func copyPassword() {
        guard let item else { return }
        Task { await viewModel.copyPassword(item) }
    }

    func confirmDeletion() {
        pendingDeletion = item
    }

    /// Decrypts the password and note, and opens the editor.
    func startEditing() {
        hapticTaps += 1
        guard let item else { return }
        editing = viewModel.editDraft(for: item)
    }

    /// Dismisses the view once the item is gone, if `dismissesWhenDeleted` is
    /// true.
    func itemRemoved() {
        if dismissesWhenDeleted, item == nil { dismiss() }
    }
}
