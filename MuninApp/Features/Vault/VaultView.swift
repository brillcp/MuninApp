import SwiftUI

struct VaultView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel = VaultViewModel()
    @State private var searchText = ""
    @State private var selection: PasswordItem.ID?
    @State private var sortOrder = [KeyPathComparator(\PasswordItem.lastUpdated, order: .reverse)]
    @State private var isCreating = false
    /// The item being edited, with its password and note decrypted for the editor.
    @State private var editing: EditDraft?

    private var visibleItems: [PasswordItem] {
        let filtered = searchText.isEmpty ? viewModel.items : viewModel.items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(using: sortOrder)
    }

    private var selectedItem: PasswordItem? {
        selection.flatMap { id in viewModel.items.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            Table(visibleItems, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.name) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text(item.username)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                TableColumn("Last Updated", value: \.lastUpdated) { item in
                    Text(item.lastUpdated, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
            }
            .contextMenu(forSelectionType: PasswordItem.ID.self) { ids in
                if ids.count == 1, let id = ids.first, let item = viewModel.items.first(where: { $0.id == id }) {
                    Button("Copy Password", systemImage: "doc.on.doc") {
                        Task { await viewModel.copyPassword(item, auth: auth) }
                    }
                    Button("Edit", systemImage: "pencil") { startEditing(item) }
                }
            }
            .overlay {
                if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't load your vault", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await viewModel.refresh(auth: auth) } }
                    }
                } else if viewModel.items.isEmpty {
                    if viewModel.hasLoaded {
                        ContentUnavailableView("No items", systemImage: "lock.rectangle.stack")
                    } else {
                        ProgressView()
                    }
                } else if visibleItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Vault")
            .searchable(text: $searchText, prompt: "Search all items")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Create Item", systemImage: "plus.square.on.square") {
                        isCreating = true
                    }
                }
            }
            .inspector(isPresented: Binding(
                get: { selectedItem != nil },
                set: { if !$0 { selection = nil } }
            )) {
                if let item = selectedItem {
                    PasswordInspector(item: item) { ciphertext, field in
                        try viewModel.decrypt(ciphertext, field: field, auth: auth)
                    } onCopyPassword: {
                        Task { await viewModel.copyPassword(item, auth: auth) }
                    } onEdit: {
                        startEditing(item)
                    }
                    .id(item.id)
                }
            }
            .task { await viewModel.refresh(auth: auth) }
            .sheet(isPresented: $isCreating) {
                PasswordEditorView { fields in
                    try await viewModel.create(fields, auth: auth)
                }
            }
            .sheet(item: $editing) { draft in
                PasswordEditorView(fields: draft.fields, isEditing: true) { fields in
                    try await viewModel.update(draft.item, with: fields, auth: auth)
                }
            }
        }
    }
}

extension VaultView {
    /// Decrypts the password and note so the editor can show them.
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

#Preview {
    VaultView()
        .environment(AuthManager())
}
