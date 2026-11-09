import SwiftUI
import UniformTypeIdentifiers

/// A view that shows the password list and the selected password's detail,
/// and handles creating, editing, deleting, and importing passwords.
struct VaultView: View {
    /// The subscription status; without a subscription, the vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// The AutoFill status, which shows a banner while AutoFill is off.
    @Environment(AutoFillSetup.self) private var autoFill
    @State private var isCreating = false
    /// The item being edited, with its password and note decrypted for the editor.
    @State private var editing: VaultViewModel.EditDraft?
    @State private var pendingDeletion: PasswordItem?
    @State private var isPickingImportFile = false
    /// A Boolean value that indicates whether the search field has focus on macOS.
    @FocusState private var isSearchFocused: Bool
    /// The trigger that lets ⌘F focus the search field on macOS.
    @State private var searchFocusRequest = SearchFocusRequest()
    /// The CSV import in progress.
    @State private var importer: PasswordImporter
    /// A counter that toolbar buttons increment to play a light haptic.
    @State private var hapticTaps = 0
    /// A Boolean value that indicates whether the detail panel is visible on
    /// macOS. It follows the selection one update later; see `columns`.
    @State private var isDetailVisible = false
    /// The item shown in the detail panel on macOS. It persists after
    /// deselection so the panel animates out with its content.
    @State private var panelItem: PasswordItem?

    /// The passwords and their selection.
    @Bindable var viewModel: VaultViewModel
    /// The 2FA accounts, which receive 2FA secrets from an imported CSV.
    let twoFactorModel: TwoFactorViewModel

    /// Creates the vault view.
    ///
    /// - Parameters:
    ///   - viewModel: The passwords and their selection.
    ///   - twoFactorModel: The 2FA accounts, which receive 2FA secrets from an imported CSV.
    init(viewModel: VaultViewModel, twoFactorModel: TwoFactorViewModel) {
        _viewModel = Bindable(viewModel)
        self.twoFactorModel = twoFactorModel
        _importer = State(initialValue: PasswordImporter(vaultModel: viewModel, twoFactorModel: twoFactorModel))
    }

    var body: some View {
        @Bindable var importer = importer
        columns
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
            .task(viewModel.refresh)
            .onChange(of: autoFill.isEnabled, autoFillChanged)
            .sheet(isPresented: $isCreating) {
                PasswordEditorView { fields in
                    try viewModel.create(fields)
                }
            }
            .confirmationDialog("vault.delete.title", item: $pendingDeletion, titleVisibility: .visible) { item in
                Button(LocalizedKey("vault.delete.button", item.name), role: .destructive) {
                    viewModel.delete(item)
                }
            } message: { item in
                Text(LocalizedKey("vault.delete.message", item.name))
            }
            .sheet(item: $editing) { draft in
                PasswordEditorView(fields: draft.fields, isEditing: true) { fields in
                    try viewModel.update(draft.item, with: fields)
                }
            }
            .fileImporter(isPresented: $isPickingImportFile, allowedContentTypes: [.commaSeparatedText]) { result in
                if case .success(let url) = result { prepareImport(from: url) }
            }
            .confirmationDialog("import.confirm.title", item: $importer.plan, titleVisibility: .visible) { plan in
                Button(plan.twoFactorAccounts.isEmpty
                       ? LocalizedKey("import.confirm.button", plan.newItems.count)
                       : LocalizedKey("import.confirm.buttonAll")) { runImport(plan) }
                    .disabled(plan.newItems.isEmpty && plan.twoFactorAccounts.isEmpty)
            } message: { plan in
                Text(plan.twoFactorAccounts.isEmpty
                     ? LocalizedKey("import.confirm.message", plan.newItems.count, plan.duplicateCount)
                     : LocalizedKey("import.confirm.messageWithCodes", plan.newItems.count, plan.twoFactorAccounts.count, plan.duplicateCount))
            }
            .alert("import.title", item: $importer.message) { _ in
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
                    .glassEffect(in: .rect(cornerRadius: DesignKit.Spacing.Primitive.s16))
                    .padding()
                }
            }
    }
}

private extension VaultView {
    /// The list and the detail.
    ///
    /// On macOS, the detail floats over the list's trailing edge as a glass
    /// panel with Close and Edit (⌘E) buttons. The panel stays in the view
    /// hierarchy and is hidden rather than removed, because inserting it with a
    /// transition also animates the form's first layout. Selecting a password
    /// fills the panel without animation; one update later, the panel slides
    /// and fades in. Switching between passwords doesn't animate. While the
    /// panel closes, `panelItem` keeps the last item so its content animates
    /// out with it.
    ///
    /// A nested `NavigationSplitView` adds the outer sidebar's width as a
    /// leading inset, and `HSplitView` and inspectors don't animate the panel
    /// smoothly, so the panel is an overlay instead.
    ///
    /// On iOS, a `NavigationSplitView` pushes the detail when a row is tapped
    /// on iPhone.
    @ViewBuilder
    var columns: some View {
        #if os(macOS)
        NavigationStack {
            listColumn
                .overlay(alignment: .trailing) {
                    if isDetailVisible {
                        PasswordDetail(item: panelItem, viewModel: viewModel)
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
            PasswordDetail(item: viewModel.selectedItem, viewModel: viewModel)
        }
        #endif
    }

    /// The list's navigation chrome: the title, the toolbar, and on macOS, the
    /// search field and CSV drop target.
    ///
    /// The search field gains focus when the vault unlocks, and ⌘F focuses it
    /// again. The list itself is ``VaultPasswordList``, a separate view that
    /// limits invalidation.
    var listColumn: some View {
        VaultPasswordList(
            viewModel: viewModel,
            pendingDeletion: $pendingDeletion,
            onEdit: startEditing
        )
        .navigationTitle("vault.title")
        .navigationSubtitle(LocalizedKey("vault.subtitle", viewModel.items.count))
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if subscriptions.isReadOnly {
                ReadOnlyBanner()
            } else if subscriptions.isInGracePeriod {
                BillingIssueBanner()
            } else if autoFill.showsBanner {
                AutoFillBanner()
            }
        }
        #if os(macOS)
        .dropDestination(for: URL.self) { urls, _ in
            guard !subscriptions.isReadOnly,
                  let url = urls.first(where: { $0.pathExtension.lowercased() == "csv" }) else { return false }
            prepareImport(from: url)
            return true
        }
        .searchable(text: $viewModel.searchText, prompt: "vault.search.prompt")
        .searchFocused($isSearchFocused)
        .focusedSceneValue(\.searchFocusRequest, searchFocusRequest)
        .onChange(of: searchFocusRequest.count) { isSearchFocused = true }
        .task { isSearchFocused = true }
        #endif
    }

    /// The toolbar's buttons.
    ///
    /// On macOS, Create follows the title, and Import and Lock sit at the
    /// trailing edge; Edit and Delete live in the detail panel. On iOS, the
    /// toolbar shows Sort, Import, and Create.
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) { LockToolbarButton() }
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { createButton }
        ToolbarSpacer(.flexible, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            importButton
        }
        ToolbarItem(placement: .primaryAction) { sortMenu }
        #else
        ToolbarItem(placement: .confirmationAction) { createButton }
        ToolbarItemGroup(placement: .secondaryAction) {
            importButton
            sortMenu
        }
        #endif
    }

    /// A menu that sorts the list by title or date edited, ascending or descending.
    var sortMenu: some View {
        Menu("vault.sort", systemImage: DesignKit.Icon.sort) {
            Picker("vault.sort", selection: $viewModel.sortColumn) {
                Label("vault.sort.title", systemImage: DesignKit.Icon.sortByTitle)
                    .tag(VaultViewModel.SortColumn.title)
                Label("vault.sort.dateEdited", systemImage: DesignKit.Icon.sortByDateEdited)
                    .tag(VaultViewModel.SortColumn.dateEdited)
            }
            .pickerStyle(.inline)
            Picker("vault.sort.direction", selection: $viewModel.sortDirection) {
                Label("vault.sort.ascending", systemImage: DesignKit.Icon.ascending)
                    .tag(SortOrder.forward)
                Label("vault.sort.descending", systemImage: DesignKit.Icon.descending)
                    .tag(SortOrder.reverse)
            }
            .pickerStyle(.inline)
        }
        .sensoryFeedback(.selection, trigger: viewModel.sortOrder)
    }

    /// A button that opens the New Password sheet (⌘N).
    var createButton: some View {
        Button("vault.createItem", systemImage: DesignKit.Icon.createPassword) {
            hapticTaps += 1
            isCreating = true
        }
        .buttonStyle(.glassProminent)
        .disabled(subscriptions.isReadOnly)
        .keyboardShortcut("n")
    }

    /// A button that opens the CSV file picker.
    ///
    /// The button is disabled until the vault loads and while an import runs.
    var importButton: some View {
        Button("import.button", systemImage: DesignKit.Icon.importFile) {
            hapticTaps += 1
            isPickingImportFile = true
        }
        .disabled(!viewModel.hasLoaded || viewModel.importProgress != nil || subscriptions.isReadOnly)
    }

    /// Reads a CSV file and asks the user to confirm the import.
    func prepareImport(from url: URL) {
        Task { await importer.prepare(from: url) }
    }

    /// Imports the confirmed plan.
    func runImport(_ plan: VaultViewModel.ImportPlan) {
        Task { await importer.run(plan) }
    }

    /// Registers the AutoFill credential identities once AutoFill is on,
    /// because the system keeps them only while it's enabled.
    func autoFillChanged() {
        if autoFill.isEnabled == true { AutoFillIdentities.replaceAll(with: viewModel.items) }
    }

    /// Decrypts the item's password and note and opens the editor with them.
    func startEditing(_ item: PasswordItem) {
        editing = viewModel.editDraft(for: item)
    }
}

/// A row that shows a password's website icon, name, and username.
struct PasswordTitleCell: View {
    /// The item to display.
    let item: PasswordItem

    var body: some View {
        #if os(iOS)
        let spacing: CGFloat = DesignKit.Spacing.Primitive.s16
        let vertical: CGFloat = DesignKit.Spacing.Primitive.s6
        #else
        let spacing: CGFloat = DesignKit.Spacing.Primitive.s12
        let vertical: CGFloat = DesignKit.Spacing.Primitive.s8
        #endif
        HStack(spacing: spacing) {
            WebsiteIcon(url: item.url)
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s4) {
                Text(item.name)
                if !item.username.isEmpty {
                    Text(item.username)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, vertical)
    }
}
