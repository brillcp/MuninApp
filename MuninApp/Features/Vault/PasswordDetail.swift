import SwiftUI

/// A password's detail: the inspector, with editing and deleting handled here.
///
/// Used by the Vault (the Mac panel, and the detail column on iPhone and iPad)
/// and by Search. On iOS it adds Edit (⌘E) to the toolbar; the Mac panel has
/// its own Edit button in its header. Delete, at the bottom of the inspector,
/// asks first. When `dismissesWhenDeleted` is set (Search), it goes back once
/// the item is gone.
struct PasswordDetail: View {
    @Environment(AuthManager.self) private var auth
    /// Read-only without a subscription: no editing or deleting.
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    /// The item being edited, with its password and note decrypted.
    @State private var editing: VaultViewModel.EditDraft?
    /// The item waiting for delete confirmation.
    @State private var pendingDeletion: PasswordItem?
    /// Bumped by Edit for a light haptic.
    @State private var hapticTaps = 0

    /// The item to show; nil shows nothing.
    let item: PasswordItem?
    /// Decrypts, copies, edits and deletes the item.
    let viewModel: VaultViewModel
    /// Goes back when the item disappears, for a detail pushed from Search.
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
                try viewModel.update(draft.item, with: fields, auth: auth)
            }
        }
        .confirmationDialog("vault.delete.title", item: $pendingDeletion, titleVisibility: .visible) { item in
            Button(LocalizedKey("vault.delete.button", item.name), role: .destructive) {
                viewModel.delete(item, auth: auth)
            }
        } message: { item in
            Text(LocalizedKey("vault.delete.message", item.name))
        }
        .onChange(of: item == nil, itemRemoved)
    }
}

private extension PasswordDetail {
    /// Decrypts one of the item's fields for the inspector.
    func decrypt(_ ciphertext: String, field: String) throws -> String {
        try viewModel.decrypt(ciphertext, field: field, auth: auth)
    }

    /// Copies the password and bumps the item's last updated time.
    func copyPassword() {
        guard let item else { return }
        Task { await viewModel.copyPassword(item, auth: auth) }
    }

    /// Asks before deleting.
    func confirmDeletion() {
        pendingDeletion = item
    }

    /// Decrypts the password and note and opens the editor with them.
    func startEditing() {
        hapticTaps += 1
        guard let item else { return }
        editing = viewModel.editDraft(for: item, auth: auth)
    }

    /// Goes back once the item is gone, if this detail was pushed from Search.
    func itemRemoved() {
        if dismissesWhenDeleted, item == nil { dismiss() }
    }
}
