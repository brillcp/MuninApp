import SwiftUI

/// A view that shows the card list and the selected card's detail, and
/// handles creating, editing, and deleting cards.
struct CardsView: View {
    /// The subscription status; without a subscription, the vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// A Boolean value that indicates whether the New Card sheet is presented.
    @State private var isCreating = false
    /// The card being edited, with every field decrypted for the editor.
    @State private var editing: CardsViewModel.EditDraft?
    /// The card awaiting delete confirmation.
    @State private var pendingDeletion: CardItem?
    /// A Boolean value that indicates whether the search field has focus on macOS.
    @FocusState private var isSearchFocused: Bool
    /// The trigger that lets ⌘F focus the search field on macOS.
    @State private var searchFocusRequest = SearchFocusRequest()
    /// A counter that toolbar buttons increment to play a light haptic.
    @State private var hapticTaps = 0
    /// A Boolean value that indicates whether the detail panel is visible on
    /// macOS. It follows the selection one update later; see `columns`.
    @State private var isDetailVisible = false
    /// The card shown in the detail panel on macOS. It persists after
    /// deselection so the panel animates out with its content.
    @State private var panelItem: CardItem?

    /// The cards and their selection.
    @Bindable var viewModel: CardsViewModel

    var body: some View {
        columns
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
            .task(viewModel.refresh)
            .sheet(isPresented: $isCreating) {
                CardEditorView { fields in
                    try viewModel.create(fields)
                }
            }
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
    }
}

private extension CardsView {
    /// The list and the detail.
    ///
    /// On macOS, the detail floats over the list's trailing edge as a glass
    /// panel, the same way as the password panel; see ``VaultView``. On iOS, a
    /// `NavigationSplitView` pushes the detail when a row is tapped on iPhone.
    @ViewBuilder
    var columns: some View {
        #if os(macOS)
        NavigationStack {
            listColumn
                .overlay(alignment: .trailing) {
                    if isDetailVisible {
                        CardDetail(item: panelItem, viewModel: viewModel)
                    }
                }
                .onChange(of: viewModel.selectedItem) { _, newItem in
                    if let newItem { panelItem = newItem }
                    isDetailVisible = newItem != nil
                }
                .animation(DesignKit.Motion.quickBouncy, value: isDetailVisible)
        }
        #else
        NavigationSplitView {
            listColumn
        } detail: {
            CardDetail(item: viewModel.selectedItem, viewModel: viewModel)
        }
        #endif
    }

    /// The list's navigation chrome: the title, the toolbar, the subscription
    /// banners, and on macOS, the search field.
    var listColumn: some View {
        CardList(viewModel: viewModel, pendingDeletion: $pendingDeletion, onEdit: startEditing)
            .leadingNavigationTitle("cards.title", subtitle: Text(LocalizedKey("vault.subtitle", viewModel.items.count)), showsLockButton: true)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                SubscriptionBanners()
            }
            #if os(macOS)
            .searchable(text: $viewModel.searchText, prompt: "cards.search.prompt")
            .searchFocused($isSearchFocused)
            .focusedSceneValue(\.searchFocusRequest, searchFocusRequest)
            .onChange(of: searchFocusRequest.count, focusSearch)
            #endif
    }

    /// The toolbar's New Card button.
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { createButton }
        #else
        ToolbarItem(placement: .confirmationAction) { createButton }
        #endif
    }

    /// A button that opens the New Card sheet (⌘N).
    var createButton: some View {
        Button("cards.createItem", systemImage: DesignKit.Icon.createCard, action: startCreating)
            .buttonStyle(.glassProminent)
            .disabled(subscriptions.isReadOnly)
            .keyboardShortcut("n")
    }

    /// Opens the New Card sheet.
    func startCreating() {
        hapticTaps += 1
        isCreating = true
    }

    /// Decrypts every field of the card and opens the editor with them.
    func startEditing(_ item: CardItem) {
        editing = viewModel.editDraft(for: item)
    }

    #if os(macOS)
    /// Focuses the search field, for ⌘F.
    func focusSearch() {
        isSearchFocused = true
    }
    #endif
}
