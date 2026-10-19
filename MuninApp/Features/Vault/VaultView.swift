import SwiftUI
import UniformTypeIdentifiers

struct VaultView: View {
    @Environment(AuthManager.self) private var auth
    @Bindable var viewModel: VaultViewModel
    @State private var isCreating = false
    /// The item being edited, with its password and note decrypted for the editor.
    @State private var editing: EditDraft?
    @State private var pendingDeletion: PasswordItem?
    @State private var isPickingImportFile = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchFocusRequest = SearchFocusRequest()
    @State private var importPlan: VaultViewModel.ImportPlan?
    /// Shown after an import: how many were added, or why the file couldn't be read.
    @State private var importMessage: String?

    var body: some View {
        columns
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
        .fileImporter(isPresented: $isPickingImportFile, allowedContentTypes: [.commaSeparatedText]) { result in
            if case .success(let url) = result { prepareImport(from: url) }
        }
        .confirmationDialog("import.confirm.title", item: $importPlan, titleVisibility: .visible) { plan in
            Button(LocalizedKey("import.confirm.button", plan.newItems.count)) {
                Task {
                    let saved = await viewModel.runImport(plan, auth: auth)
                    importMessage = Localized("import.done.message", saved)
                }
            }
            .disabled(plan.newItems.isEmpty)
        } message: { plan in
            Text(LocalizedKey("import.confirm.message", plan.newItems.count, plan.duplicateCount))
        }
        .alert("import.title", item: $importMessage) { _ in
            Button("global.done") {}
        } message: { message in
            Text(message)
        }
        .overlay(alignment: .bottom) {
            if let progress = viewModel.importProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text(LocalizedKey("import.progress", progress.done, progress.total))
                }
                .padding()
                .glassEffect(in: .rect(cornerRadius: 16))
                .padding()
            }
        }
    }
}

extension VaultView {
    /// Mac: list and detail side by side in an HSplitView. A NavigationSplitView
    /// nested in the sidebar tab gave the detail the outer sidebar's width as an
    /// extra leading inset. iOS: a NavigationSplitView, so tapping a row pushes
    /// the detail on iPhone.
    @ViewBuilder
    private var columns: some View {
        #if os(macOS)
        NavigationStack {
            HSplitView {
                listColumn
                    .frame(minWidth: 320, idealWidth: 460, maxHeight: .infinity)
                VaultItemDetail(viewModel: viewModel, pendingDeletion: $pendingDeletion, onEdit: startEditing)
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #else
        NavigationSplitView {
            listColumn
        } detail: {
            VaultItemDetail(viewModel: viewModel, pendingDeletion: $pendingDeletion, onEdit: startEditing)
        }
        #endif
    }

    /// The list's navigation chrome (title, search, toolbar, import drop).
    /// The list itself is `VaultPasswordList`, its own invalidation boundary.
    private var listColumn: some View {
        VaultPasswordList(
            viewModel: viewModel,
            pendingDeletion: $pendingDeletion,
            onEdit: startEditing
        )
            #if os(macOS)
            // Drag a CSV export from Finder onto the list to import it.
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { $0.pathExtension.lowercased() == "csv" }) else { return false }
                prepareImport(from: url)
                return true
            }
            #endif
            .navigationTitle("vault.title")
            .barkToolbar(title: "vault.title")
            .searchable(text: $viewModel.searchText, prompt: "vault.search.prompt")
            .searchFocused($isSearchFocused)
            // ⌘F (Edit ▸ Find) focuses the search field.
            .focusedSceneValue(\.searchFocusRequest, searchFocusRequest)
            .onChange(of: searchFocusRequest.count) { isSearchFocused = true }
            .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("import.button", systemImage: "square.and.arrow.down") {
                isPickingImportFile = true
            }
            .disabled(!viewModel.hasLoaded || viewModel.importProgress != nil)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("vault.createItem", systemImage: "plus.square.on.square") {
                isCreating = true
            }
            .buttonStyle(.glassProminent)
            // Toolbar items don't pick up the app-wide tint, so set it here.
            .tint(.accent)
        }
    }

    /// Reads the CSV (picked or dropped from Finder) in memory and asks to confirm.
    private func prepareImport(from url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let rows = try PasswordCSVParser.parse(try Data(contentsOf: url))
            importPlan = viewModel.planImport(rows)
        } catch {
            importMessage = error.localizedDescription
        }
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
/// The password table (Mac) or list (iOS), with its context menu and empty
/// states. Mac: a sortable table. iOS: a list whose rows push the detail
/// column (a Table doesn't navigate when the split view is collapsed on iPhone).
private struct VaultPasswordList: View {
    @Bindable var viewModel: VaultViewModel
    @Binding var pendingDeletion: PasswordItem?
    let onEdit: (PasswordItem) -> Void

    @Environment(AuthManager.self) private var auth

    var body: some View {
        rows
            .contextMenu(forSelectionType: PasswordItem.ID.self) { ids in
                if ids.count == 1, let id = ids.first, let item = viewModel.items.first(where: { $0.id == id }) {
                    Button("vault.copyPassword", systemImage: "doc.on.doc") {
                        Task { await viewModel.copyPassword(item, auth: auth) }
                    }
                    Button("global.edit", systemImage: "square.and.pencil") { onEdit(item) }
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
    }

    @ViewBuilder
    private var rows: some View {
        #if os(macOS)
        Table(viewModel.visibleItems, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
            TableColumn("vault.column.title", value: \.name) { item in
                PasswordTitleCell(name: item.name, username: item.username, url: item.url)
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
                PasswordTitleCell(name: item.name, username: item.username, url: item.url)
            }
        }
        .listStyle(.plain)
        #endif
    }
}

/// The selected password, or a placeholder. Its own view, so it only updates
/// when the selection or that item changes.
private struct VaultItemDetail: View {
    let viewModel: VaultViewModel
    @Binding var pendingDeletion: PasswordItem?
    let onEdit: (PasswordItem) -> Void

    @Environment(AuthManager.self) private var auth

    var body: some View {
        if let item = viewModel.selectedItem {
            PasswordInspector(item: item) { ciphertext, field in
                try viewModel.decrypt(ciphertext, field: field, auth: auth)
            } onCopyPassword: {
                Task { await viewModel.copyPassword(item, auth: auth) }
            } onEdit: {
                onEdit(item)
            } onDelete: {
                pendingDeletion = item
            }
            .id(item.id)
        } else {
            ContentUnavailableView("vault.selectItem", systemImage: "lock.rectangle.stack")
        }
    }
}

private struct PasswordTitleCell: View {
    let name: String
    let username: String
    let url: String

    var body: some View {
        HStack(spacing: 12) {
            WebsiteIcon(url: url)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(username)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
    VaultView(viewModel: VaultViewModel(session: VaultSession()))
        .environment(AuthManager())
}
