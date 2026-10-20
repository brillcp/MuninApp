import SwiftUI
import UniformTypeIdentifiers

/// The Vault screen: the password list, the selected password's detail,
/// and creating, editing, deleting and importing passwords.
struct VaultView: View {
    @Environment(AuthManager.self) private var auth
    /// The passwords and their selection.
    @Bindable var viewModel: VaultViewModel
    /// Shows the New Password sheet.
    @State private var isCreating = false
    /// The item being edited, with its password and note decrypted for the editor.
    @State private var editing: EditDraft?
    /// The item waiting for delete confirmation.
    @State private var pendingDeletion: PasswordItem?
    /// Shows the CSV file picker.
    @State private var isPickingImportFile = false
    /// Mac: whether the search field has keyboard focus.
    @FocusState private var isSearchFocused: Bool
    /// Mac: lets ⌘F focus this screen's search field.
    @State private var searchFocusRequest = SearchFocusRequest()
    /// A parsed CSV waiting for import confirmation.
    @State private var importPlan: VaultViewModel.ImportPlan?
    /// Shown after an import: how many were added, or why the file couldn't be read.
    @State private var importMessage: String?
    /// Bumped by toolbar buttons for a light haptic.
    @State private var hapticTaps = 0
    /// Mac: whether the detail panel is slid in. Follows the selection, one
    /// update later (see `columns`).
    @State private var isDetailVisible = false
    /// Mac: the item that was showing, kept only while the panel slides out.
    @State private var closingItem: PasswordItem?

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
    /// The list and the detail.
    ///
    /// Mac: the list, with the detail floating over its trailing edge as a
    /// glass panel with Close and Edit buttons. The panel is always in the
    /// hierarchy, just hidden: inserting it with a transition also animated the
    /// Form's first layout, so its content grew in from a zero frame. Selecting
    /// a password fills the panel without animation, and one update later the
    /// panel slides and fades in with a bounce. Switching between passwords
    /// doesn't animate. While it closes, the last item stays in the panel so it
    /// fades out with it instead of going blank.
    ///
    /// A NavigationSplitView nested in the sidebar tab gave the detail the
    /// outer sidebar's width as an extra leading inset, and an HSplitView or
    /// an inspector couldn't animate the panel in well.
    ///
    /// iOS: a NavigationSplitView, so tapping a row pushes the detail on iPhone.
    @ViewBuilder
    private var columns: some View {
        #if os(macOS)
        NavigationStack {
            listColumn
                .overlay(alignment: .trailing) {
                    VaultItemDetail(item: viewModel.selectedItem ?? closingItem, viewModel: viewModel, pendingDeletion: $pendingDeletion, onEdit: startEditing)
                        .safeAreaInset(edge: .top, spacing: DesignKit.Spacing.Primitive.s0) {
                            HStack {
                                Button("global.close", systemImage: "xmark") {
                                    hapticTaps += 1
                                    viewModel.selection = nil
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .help("global.close")
                                Spacer()
                                Button("global.edit", systemImage: "square.and.pencil") {
                                    hapticTaps += 1
                                    if let item = viewModel.selectedItem { startEditing(item) }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .help("global.edit")
                            }
                            .padding([.horizontal, .top], DesignKit.Spacing.Primitive.s12)
                        }
                        .frame(width: 340)
                        .frame(maxHeight: .infinity)
                        .glassEffect(in: .rect(cornerRadius: 20))
                        .padding(DesignKit.Spacing.Primitive.s12)
                        .offset(x: isDetailVisible ? 0 : 48)
                        .opacity(isDetailVisible ? 1 : 0)
                        .allowsHitTesting(isDetailVisible)
                        .accessibilityHidden(!isDetailVisible)
                }
                .onChange(of: viewModel.selectedItem) { oldItem, newItem in
                    switch (oldItem, newItem) {
                    case (nil, .some):
                        withAnimation(.bouncy(duration: 0.25)) { isDetailVisible = true }
                    case (.some(let oldItem), nil):
                        closingItem = oldItem
                        withAnimation(.bouncy(duration: 0.25)) {
                            isDetailVisible = false
                        } completion: {
                            closingItem = nil
                        }
                    default:
                        break
                    }
                }
        }
        #else
        NavigationSplitView {
            listColumn
        } detail: {
            VaultItemDetail(item: viewModel.selectedItem, viewModel: viewModel, pendingDeletion: $pendingDeletion, onEdit: startEditing)
        }
        #endif
    }

    /// The list's navigation chrome: title, toolbar, and on the Mac the search
    /// field (⌘F focuses it) and CSV drop from Finder.
    ///
    /// The list itself is `VaultPasswordList`, its own invalidation boundary.
    private var listColumn: some View {
        VaultPasswordList(
            viewModel: viewModel,
            pendingDeletion: $pendingDeletion,
            onEdit: startEditing
        )
            #if os(macOS)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { $0.pathExtension.lowercased() == "csv" }) else { return false }
                prepareImport(from: url)
                return true
            }
            #endif
            .barkToolbar(title: "vault.title", subtitle: "\(viewModel.items.count) items")
            #if os(macOS)
            .searchable(text: $viewModel.searchText, prompt: "vault.search.prompt")
            .searchFocused($isSearchFocused)
            .focusedSceneValue(\.searchFocusRequest, searchFocusRequest)
            .onChange(of: searchFocusRequest.count) { isSearchFocused = true }
            #endif
            .toolbar { toolbarContent }
    }

    /// The toolbar's buttons.
    ///
    /// Mac: Create after the title, then Import and Lock at the far right.
    /// Edit and Delete are in the detail panel. iOS: Import and Create.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { createButton }
        ToolbarSpacer(.flexible, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            importButton
            LockToolbarButton()
        }
        #else
        ToolbarItem(placement: .primaryAction) { importButton }
        ToolbarItem(placement: .confirmationAction) { createButton }
        #endif
    }

    /// Opens the New Password sheet. Prominent glass in the accent colour.
    private var createButton: some View {
        Button("vault.createItem", systemImage: "plus.square.on.square") {
            hapticTaps += 1
            isCreating = true
        }
        .buttonStyle(.glassProminent)
        .tint(.accent)
    }

    /// Opens the CSV file picker. Disabled until loaded and while an import runs.
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

    /// Decrypts the item's password and note and opens the editor with them.
    private func startEditing(_ item: PasswordItem) {
        guard let password = try? viewModel.decrypt(item.encryptedPassword, field: "password", auth: auth),
              let note = try? viewModel.decrypt(item.encryptedNote, field: "note", auth: auth) else { return }
        editing = EditDraft(item: item, fields: PasswordFields(
            name: item.name, url: item.url, username: item.username, password: password, note: note
        ))
    }
}

/// An item being edited and its decrypted fields, presented as a sheet item.
private struct EditDraft: Identifiable {
    /// The item as stored.
    let item: PasswordItem
    /// Its fields in plain text, for the editor.
    let fields: PasswordFields
    var id: UUID { item.id }
}

/// The password table (Mac) or list (iOS), with its context menu and empty
/// states.
///
/// Mac: a sortable table; Escape deselects the password, which closes its
/// detail. iOS: a list whose rows push the detail column (a Table doesn't
/// navigate when the split view is collapsed on iPhone).
private struct VaultPasswordList: View {
    /// The passwords, selection and sort order.
    @Bindable var viewModel: VaultViewModel
    /// Set by the context menu's Delete, to ask for confirmation.
    @Binding var pendingDeletion: PasswordItem?
    /// Called by the context menu's Edit.
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

    /// The table or list itself.
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
        .onExitCommand { viewModel.selection = nil }
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

/// The selected password's detail, or nothing. Its own view, so it only
/// updates when the selection or that item changes.
///
/// iOS adds an Edit button to the toolbar; on the Mac, Edit is in the panel's
/// header. Delete is at the bottom of the detail on both.
private struct VaultItemDetail: View {
    /// The item to show; nil shows nothing.
    let item: PasswordItem?
    /// Decrypts and copies the item's fields.
    let viewModel: VaultViewModel
    /// Set by the detail's Delete, to ask for confirmation.
    @Binding var pendingDeletion: PasswordItem?
    /// Called by Edit.
    let onEdit: (PasswordItem) -> Void

    /// Bumped by buttons for a light haptic.
    @State private var hapticTaps = 0

    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            if let item {
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("global.edit", systemImage: "square.and.pencil") {
                    hapticTaps += 1
                    if let item = viewModel.selectedItem { onEdit(item) }
                }
                .disabled(viewModel.selectedItem == nil)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        #endif
    }
}

/// A password row: website icon, name, and the username underneath.
private struct PasswordTitleCell: View {
    /// The item's name.
    let name: String
    /// The item's username.
    let username: String
    /// The item's website, for the icon.
    let url: String

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            WebsiteIcon(url: url)
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
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
    /// A load error to show, if the list is empty because loading failed.
    let errorMessage: String?
    /// Whether there are no passwords.
    let isEmpty: Bool
    /// Whether the first load has finished; before that a spinner shows.
    let hasLoaded: Bool
    /// Set when a search matches nothing.
    let searchText: String?
    /// Called by Try Again.
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
