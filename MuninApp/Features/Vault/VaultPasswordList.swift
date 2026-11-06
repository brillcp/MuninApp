import SwiftUI

/// A view that shows the passwords with a context menu and empty states.
///
/// On macOS, it's a sortable table, and Escape deselects the password to close
/// its detail. On iOS, it's a list whose rows push the detail column, because
/// a `Table` doesn't navigate when the split view is collapsed.
struct VaultPasswordList: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SubscriptionManager.self) private var subscriptions

    /// The passwords, selection and sort order.
    @Bindable var viewModel: VaultViewModel
    /// The item to delete, set by the context menu to request confirmation.
    @Binding var pendingDeletion: PasswordItem?
    /// The action that the context menu's Edit item performs.
    let onEdit: (PasswordItem) -> Void

    var body: some View {
        rows
            .contextMenu(forSelectionType: PasswordItem.ID.self) { ids in
                if ids.count == 1, let id = ids.first, let item = viewModel.items.first(where: { $0.id == id }) {
                    Button("vault.copyUsername", systemImage: DesignKit.Icon.username) {
                        Pasteboard.copy(item.username)
                    }
                    .disabled(item.username.isEmpty)
                    .tint(.primary)
                    Button("vault.copyPassword", systemImage: DesignKit.Icon.copy) {
                        Task { await viewModel.copyPassword(item, auth: auth) }
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
                VaultEmptyState(
                    errorMessage: viewModel.items.isEmpty ? viewModel.errorMessage : nil,
                    isEmpty: viewModel.items.isEmpty,
                    hasLoaded: viewModel.hasLoaded,
                    searchText: viewModel.visibleItems.isEmpty ? viewModel.searchText : nil,
                    onRetry: { Task { await viewModel.refresh(auth: auth) } }
                )
            }
    }
}

private extension VaultPasswordList {
    /// The table or list.
    ///
    /// Rows animate when items are added, deleted, imported, or filtered.
    /// When sorted by title, rows are grouped into letter sections, with an
    /// A–Z index on iPhone. When sorted by date edited, the list is flat.
    @ViewBuilder
    var rows: some View {
        List(selection: $viewModel.selection) {
            if viewModel.sections.isEmpty {
                ForEach(viewModel.visibleItems, content: row)
            } else {
                ForEach(viewModel.sections) { section in
                    Section(section.letter) {
                        ForEach(section.items, content: row)
                    }
                    #if os(iOS)
                    .sectionIndexLabel(section.letter)
                    #endif
                }
            }
        }
        .listStyle(.plain)
        .animation(DesignKit.Motion.listChange, value: viewModel.visibleItems.map(\.id))
        #if os(iOS)
        .listSectionIndexVisibility(UIDevice.current.userInterfaceIdiom == .phone ? .visible : .hidden)
        #else
        .alternatingRowBackgrounds()
        .onExitCommand { viewModel.selection = nil }
        #endif
    }

    /// A row that pushes or selects its item.
    func row(_ item: PasswordItem) -> some View {
        NavigationLink(value: item.id) {
            PasswordTitleCell(item: item)
        }
    }
}
