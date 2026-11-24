import SwiftUI

/// A view that shows the cards with a context menu and empty states.
///
/// On macOS, Escape deselects the card to close its detail. On iOS, rows push
/// the detail column.
struct CardList: View {
    /// The subscription state. Edit and Delete are disabled while the vault
    /// is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// The width the macOS sidebar covers, which the rows start after.
    @Environment(\.sidebarWidth) private var sidebarWidth

    /// The cards, selection, and search text.
    @Bindable var viewModel: CardsViewModel
    /// The card to delete, set by the context menu to request confirmation.
    @Binding var pendingDeletion: CardItem?
    /// The action that the context menu's Edit item performs.
    let onEdit: (CardItem) -> Void

    var body: some View {
        List(selection: $viewModel.selection) {
            ForEach(viewModel.visibleItems, content: row)
        }
        .listStyle(.plain)
        .animation(DesignKit.Motion.listChange, value: viewModel.visibleItems.map(\.id))
        .contextMenu(forSelectionType: CardItem.ID.self) { ids in
            if ids.count == 1, let id = ids.first, let item = viewModel.items.first(where: { $0.id == id }) {
                Button("cards.copyNumber", systemImage: DesignKit.Icon.copy) {
                    viewModel.copySensitive(item.encryptedNumber, field: .number)
                }
                .tint(.primary)
                Button("global.edit", systemImage: DesignKit.Icon.edit) { onEdit(item) }
                    .disabled(subscriptions.isReadOnly)
                    .tint(.primary)
                Divider()
                Button("global.delete", systemImage: DesignKit.Icon.delete, role: .destructive) { pendingDeletion = item }
                    .disabled(subscriptions.isReadOnly)
                    .tint(.red)
            }
        }
        .overlay {
            CardsEmptyState(
                errorMessage: viewModel.items.isEmpty ? viewModel.errorMessage : nil,
                isEmpty: viewModel.items.isEmpty,
                hasLoaded: viewModel.hasLoaded,
                searchText: viewModel.visibleItems.isEmpty ? viewModel.searchText : nil,
                onRetry: { Task { await viewModel.refresh() } }
            )
            .padding(.leading, sidebarWidth)
        }
        #if os(macOS)
        .alternatingRowBackgrounds(viewModel.visibleItems.isEmpty ? .disabled : .enabled)
        .onExitCommand { viewModel.selection = nil }
        #endif
    }
}

private extension CardList {
    /// A row that pushes or selects its card.
    func row(_ item: CardItem) -> some View {
        NavigationLink(value: item.id) {
            CardRow(name: item.name, lastDigits: item.lastDigits)
                .padding(.leading, sidebarWidth)
        }
    }
}
