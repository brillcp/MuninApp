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
    /// Bumped by toolbar buttons for a light haptic.
    @State private var hapticTaps = 0

    var body: some View {
        columns
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
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
    /// Mac: the list, with the detail as an inspector. A NavigationSplitView
    /// nested in the sidebar tab gave the detail the outer sidebar's width as an
    /// extra leading inset, and an HSplitView couldn't animate the panel in. iOS: a NavigationSplitView, so tapping a row pushes
    /// the detail on iPhone.
    @ViewBuilder
    private var columns: some View {
        #if os(macOS)
        NavigationStack {
            listColumn
                .overlay(alignment: .trailing) {
                    if viewModel.isShowingDetail {
                        VaultItemDetail(viewModel: viewModel, pendingDeletion: $pendingDeletion, onEdit: startEditing)
                            .safeAreaInset(edge: .top, spacing: 0) {
                                HStack {
                                    Button("global.close", systemImage: "xmark") {
                                        hapticTaps += 1
                                        viewModel.isShowingDetail = false
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.glass)
                                    .buttonBorderShape(.circle)
                                    .help("global.close")
                                    Spacer()
                                }
                                .padding([.horizontal, .top], 12)
                            }
                            .frame(width: 340)
                            .frame(maxHeight: .infinity)
                            .glassEffect(in: .rect(cornerRadius: 20))
                            .padding(12)
                            .transition(.offset(x: 48).combined(with: .opacity))
                    }
                }
                .animation(.bouncy(duration: 0.25), value: viewModel.isShowingDetail)
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
            #if os(macOS)
            // iOS searches in its own Search tab instead.
            .searchable(text: $viewModel.searchText, prompt: "vault.search.prompt")
            .searchFocused($isSearchFocused)
            // ⌘F (Edit ▸ Find) focuses the search field.
            .focusedSceneValue(\.searchFocusRequest, searchFocusRequest)
            .onChange(of: searchFocusRequest.count) { isSearchFocused = true }
            #endif
            .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        // Title ---> Create  [Import, Lock]  [Edit, Delete]
        ToolbarItem(placement: .primaryAction) { createButton }
        // Pushes the groups below to the far right.
        ToolbarSpacer(.flexible, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            importButton
            LockToolbarButton()
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        // Always shown, disabled without a selection, so the toolbar keeps its shape.
        ToolbarItemGroup(placement: .primaryAction) {
            Button("global.edit", systemImage: "square.and.pencil") {
                hapticTaps += 1
                if let item = viewModel.selectedItem { startEditing(item) }
            }
            .disabled(viewModel.selectedItem == nil)
            Button("global.delete", systemImage: "trash", role: .destructive) {
                hapticTaps += 1
                pendingDeletion = viewModel.selectedItem
            }
            .disabled(viewModel.selectedItem == nil)
        }
        #else
        ToolbarItem(placement: .confirmationAction) { importButton }
        ToolbarItem(placement: .primaryAction) { createButton }
        #endif
    }

    private var createButton: some View {
        Button("vault.createItem", systemImage: "plus.square.on.square") {
            hapticTaps += 1
            isCreating = true
        }
        .buttonStyle(.glassProminent)
        .tint(.accent)
    }

    private var importButton: some View {
        Button("import.button", systemImage: "folder.badge.plus") {
            hapticTaps += 1
            isPickingImportFile = true
        }
        .disabled(!viewModel.hasLoaded || viewModel.importProgress != nil)
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
                    Button("vault.copyUsername", systemImage: "person") {
                        Pasteboard.copy(item.username)
                    }
                    .disabled(item.username.isEmpty)
                    Button("vault.copyPassword", systemImage: "square.on.square") {
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
        // Escape deselects the password (and closes its detail).
        .onExitCommand { viewModel.selection = nil }
        #else
        List(viewModel.visibleItems, selection: $viewModel.selection) { item in
            NavigationLink(value: item.id) {
                PasswordTitleCell(name: item.name, username: item.username, url: item.url)
            }
        }
        .listStyle(.insetGrouped)
        #endif
    }
}

/// The selected password, or a placeholder. Its own view, so it only updates
/// when the selection or that item changes.
private struct VaultItemDetail: View {
    let viewModel: VaultViewModel
    @Binding var pendingDeletion: PasswordItem?
    let onEdit: (PasswordItem) -> Void

    @State private var hapticTaps = 0

    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            if let item = viewModel.selectedItem {
                PasswordInspector(item: item) { ciphertext, field in
                    try viewModel.decrypt(ciphertext, field: field, auth: auth)
                } onCopyPassword: {
                    Task { await viewModel.copyPassword(item, auth: auth) }
                } onDelete: {
                    pendingDeletion = item
                }
                .id(item.id)
            }
        }
        #if os(iOS)
        // iOS: Edit on the detail screen. (Mac: in VaultView's toolbar.)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("global.edit", systemImage: "square.and.pencil") {
                    hapticTaps += 1
                    if let item = viewModel.selectedItem { onEdit(item) }
                }
                .disabled(viewModel.selectedItem == nil)
            }
            // Delete is at the bottom of the detail list.
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        #endif
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
