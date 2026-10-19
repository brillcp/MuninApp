import SwiftUI

struct VaultView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: VaultViewModel
    @State private var isCreating = false
    #if os(iOS)
    @State private var isShowingSettings = false
    #endif
    /// The item being edited, with its password and note decrypted for the editor.
    @State private var editing: EditDraft?
    @State private var pendingDeletion: PasswordItem?

    init(session: VaultSession) {
        _viewModel = State(initialValue: VaultViewModel(session: session))
    }

    var body: some View {
        NavigationSplitView {
            passwordList
            .contextMenu(forSelectionType: PasswordItem.ID.self) { ids in
                if ids.count == 1, let id = ids.first, let item = viewModel.items.first(where: { $0.id == id }) {
                    Button("vault.copyPassword", systemImage: "doc.on.doc") {
                        Task { await viewModel.copyPassword(item, auth: auth) }
                    }
                    Button("global.edit", systemImage: "square.and.pencil") { startEditing(item) }
                    Divider()
                    Button("global.delete", systemImage: "trash", role: .destructive) { pendingDeletion = item }
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
            .navigationTitle("vault.title")
            .barkToolbar(title: "vault.title")
            .searchable(text: $viewModel.searchText, prompt: "vault.search.prompt")
            .toolbar { toolbarContent }
            .navigationSplitViewColumnWidth(min: 320, ideal: 460)
        } detail: {
            if let item = viewModel.selectedItem {
                PasswordInspector(item: item) { ciphertext, field in
                    try viewModel.decrypt(ciphertext, field: field, auth: auth)
                } onCopyPassword: {
                    Task { await viewModel.copyPassword(item, auth: auth) }
                } onEdit: {
                    startEditing(item)
                } onDelete: {
                    pendingDeletion = item
                }
                .id(item.id)
            } else {
                ContentUnavailableView("vault.selectItem", systemImage: "lock.rectangle.stack")
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet()
        }
        #endif
        .task { await viewModel.refresh(auth: auth) }
        .sheet(isPresented: $isCreating) {
            PasswordEditorView { fields in
                try await viewModel.create(fields, auth: auth)
            }
        }
        .confirmationDialog("vault.delete.title", item: $pendingDeletion, titleVisibility: .visible) { item in
            Button(LocalizedKey("vault.delete.button", item.name), role: .destructive) {
                Task { await viewModel.delete(item, auth: auth) }
            }
        } message: { item in
            Text(LocalizedKey("vault.delete.message", item.name))
        }
        .sheet(item: $editing) { draft in
            PasswordEditorView(fields: draft.fields, isEditing: true) { fields in
                try await viewModel.update(draft.item, with: fields, auth: auth)
            }
        }
    }
}

extension VaultView {
    /// Mac: a sortable table. iOS: a list whose rows push the detail column
    /// (a Table doesn't navigate when the split view is collapsed on iPhone).
    @ViewBuilder
    private var passwordList: some View {
        #if os(macOS)
        Table(viewModel.visibleItems, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
            TableColumn("vault.column.title", value: \.name) { item in
                PasswordTitleCell(name: item.name, username: item.username)
            }
            TableColumn("password.field.lastUpdated", value: \.lastUpdated) { item in
                Text(item.lastUpdated, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
            }
        }
        .tableStyle(.bordered)
        #else
        List(viewModel.visibleItems, selection: $viewModel.selection) { item in
            NavigationLink(value: item.id) {
                PasswordTitleCell(name: item.name, username: item.username)
            }
        }
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("vault.createItem", systemImage: "plus.square.on.square") {
                isCreating = true
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
        }
        #if os(iOS)
        ToolbarItem(placement: .primaryAction) {
            Button("settings.title", systemImage: "gearshape") { isShowingSettings = true }
        }
        #endif
    }

    private func startEditing(_ item: PasswordItem) {
        guard let password = try? viewModel.decrypt(item.encryptedPassword, field: "password", auth: auth),
              let note = try? viewModel.decrypt(item.encryptedNote, field: "note", auth: auth) else { return }
        editing = EditDraft(item: item, fields: PasswordFields(
            name: item.name, url: item.url, username: item.username, password: password, note: note
        ))
    }
}

private struct EditDraft: Identifiable {
    let item: PasswordItem
    let fields: PasswordFields
    var id: UUID { item.id }
}

/// The Title column: name with the username underneath.
private struct PasswordTitleCell: View {
    let name: String
    let username: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            Text(username)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Error, empty, loading and no-search-results states for the vault table.
private struct VaultEmptyState: View {
    let errorMessage: String?
    let isEmpty: Bool
    let hasLoaded: Bool
    /// Set when a search matches nothing.
    let searchText: String?
    let onRetry: () -> Void

    var body: some View {
        if let errorMessage {
            ContentUnavailableView {
                Label("errors.loadVault.title", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("global.tryAgain", action: onRetry)
            }
        } else if isEmpty {
            if hasLoaded {
                ContentUnavailableView("vault.empty.title", systemImage: "lock.rectangle.stack")
            } else {
                ProgressView()
            }
        } else if let searchText {
            ContentUnavailableView.search(text: searchText)
        }
    }
}

#Preview {
    VaultView(session: VaultSession())
        .environment(AuthManager())
}
