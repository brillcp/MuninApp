import SwiftUI

/// A view that shows a stored card's details and handles editing and
/// deleting it.
///
/// On iOS, Edit (⌘E) appears in the toolbar. On macOS, the panel has its own
/// Edit button in its header. Delete asks for confirmation first. When
/// `dismissesWhenDeleted` is true, the view dismisses itself once the card is
/// gone.
struct CardDetail: View {
    /// The subscription state. While the vault is read-only, Edit shows the
    /// paywall and Delete is disabled.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// The action that closes the view when the card is deleted.
    @Environment(\.dismiss) private var dismiss
    /// The card being edited, with every field decrypted.
    @State private var editing: CardsViewModel.EditDraft?
    /// The card awaiting delete confirmation.
    @State private var pendingDeletion: CardItem?
    /// A counter incremented by Edit to trigger a light haptic.
    @State private var hapticTaps = 0

    /// The card to show, or `nil` to show nothing.
    let item: CardItem?
    /// The view model that decrypts, copies, edits, and deletes the card.
    let viewModel: CardsViewModel
    /// A Boolean value that indicates whether the view dismisses itself when the
    /// card is deleted.
    var dismissesWhenDeleted = false

    var body: some View {
        Group {
            if let item {
                CardInspector(item: item, decrypt: decrypt, onCopySensitive: viewModel.copySensitive, onDelete: confirmDeletion)
                    .id(item.id)
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("global.edit", systemImage: DesignKit.Icon.edit, action: startEditing)
                    .disabled(item == nil)
                    .keyboardShortcut("e")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        #else
        .safeAreaInset(edge: .top, spacing: DesignKit.Spacing.Primitive.s0) {
            HStack {
                LockButton(systemImage: DesignKit.Icon.close, style: .clear, action: close)
                Spacer()
                LockButton(systemImage: DesignKit.Icon.edit, style: .clear, action: startEditing)
                    .keyboardShortcut("e")
            }
            .padding([.horizontal, .top], DesignKit.Spacing.Primitive.s12)
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .glassPanel()
        .padding(DesignKit.Spacing.Primitive.s12)
        .transition(.opacity.combined(with: .offset(x: DesignKit.Spacing.Primitive.s40)))
        #endif
        .sheet(item: $editing) { draft in
            CardEditorView(fields: draft.fields, isEditing: true) { fields in
                try viewModel.update(draft.item, with: fields)
            }
        }
        .confirmationDialog("cards.delete.title", item: $pendingDeletion, titleVisibility: .visible) { item in
            Button(LocalizedKey("vault.delete.button", item.name), role: .destructive) {
                viewModel.delete(item)
            }
        } message: { item in
            Text(LocalizedKey("vault.delete.message", item.name))
        }
        .onChange(of: item == nil, itemRemoved)
    }
}

private extension CardDetail {
    /// Decrypts one of the card's fields for the inspector.
    func decrypt(_ ciphertext: String, field: CardField) throws -> String {
        try viewModel.decrypt(ciphertext, field: field)
    }

    #if os(macOS)
    /// Closes the panel by deselecting the card.
    func close() {
        viewModel.selection = nil
    }
    #endif

    /// Asks for confirmation before deleting the card.
    func confirmDeletion() {
        pendingDeletion = item
    }

    /// Decrypts every field and opens the editor, or shows the paywall while
    /// the vault is read-only.
    func startEditing() {
        hapticTaps += 1
        guard !subscriptions.isReadOnly else {
            subscriptions.isPaywallPresented = true
            return
        }
        guard let item else { return }
        editing = viewModel.editDraft(for: item)
    }

    /// Dismisses the view once the card is gone, if `dismissesWhenDeleted` is
    /// true.
    func itemRemoved() {
        if dismissesWhenDeleted, item == nil { dismiss() }
    }
}
