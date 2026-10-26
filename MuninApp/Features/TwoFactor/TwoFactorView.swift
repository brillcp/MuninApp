import SwiftUI
import UniformTypeIdentifiers

/// The 2FA screen: every account's current code, with add, import, refresh and delete.
struct TwoFactorView: View {
    @Environment(AuthManager.self) private var auth
    /// Read-only without a subscription: no adding or deleting.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// Shows the Add Account sheet.
    @State private var isAdding = false
    /// The account waiting for delete confirmation.
    @State private var pendingDeletion: VaultItem?
    /// Bumped by toolbar buttons for a light haptic.
    @State private var hapticTaps = 0
    /// One clock for the code rows.
    @State private var clock = TwoFactorClock()
    /// Shows the file picker for importing a 2FA export.
    @State private var isPickingImportFile = false
    /// A read import file waiting for confirmation.
    @State private var importPlan: TwoFactorImportPlan?
    /// Shown after an import: how many were added, or why the file couldn't be read.
    @State private var importMessage: String?

    /// Loads, adds and deletes the accounts.
    let viewModel: TwoFactorViewModel

    var body: some View {
        NavigationStack {
            TwoFactorList(viewModel: viewModel, clock: clock, pendingDeletion: $pendingDeletion)
            .overlay {
                TwoFactorEmptyState(
                    errorMessage: viewModel.items.isEmpty ? viewModel.errorMessage : nil,
                    isEmpty: viewModel.items.isEmpty && viewModel.undecryptableCount == 0,
                    hasLoaded: viewModel.hasLoaded,
                    onRetry: { Task { await viewModel.refresh(auth: auth) } },
                    onAdd: { isAdding = true }
                )
            }
            .navigationTitle("codes.title")
            .navigationSubtitle(LocalizedKey("codes.subtitle", viewModel.items.count))
            .navigationSplitViewStyle(.prominentDetail)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if subscriptions.isReadOnly {
                    ReadOnlyBanner()
                } else if subscriptions.isInGracePeriod {
                    BillingIssueBanner()
                }
            }
            .refreshable { await viewModel.refresh(auth: auth) }
            .task { await viewModel.refresh(auth: auth) }
            .task(clock.run)
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
            .sheet(isPresented: $isAdding) {
                AddAccountView { accounts in
                    try await viewModel.add(accounts, auth: auth)
                }
            }
            .fileImporter(isPresented: $isPickingImportFile, allowedContentTypes: [.plainText, .text], onCompletion: importFilePicked)
            .confirmationDialog("codes.import.confirm.title", item: $importPlan, titleVisibility: .visible) { plan in
                Button(LocalizedKey("codes.import.confirm.button", plan.accounts.count)) { runImport(plan) }
                    .disabled(plan.accounts.isEmpty)
            } message: { plan in
                Text(plan.failedLines > 0
                     ? LocalizedKey("codes.import.confirm.messageWithFailures", plan.accounts.count, plan.duplicateCount, plan.failedLines)
                     : LocalizedKey("codes.import.confirm.message", plan.accounts.count, plan.duplicateCount))
            }
            .alert("codes.import.title", item: $importMessage) { _ in
                Button("global.done") {}
            } message: { message in
                Text(message)
            }
            .confirmationDialog("codes.delete.title", item: $pendingDeletion, titleVisibility: .visible) { item in
                Button(LocalizedKey("codes.delete.button", item.account.title), role: .destructive) {
                    Task { await viewModel.delete(item, auth: auth) }
                }
            } message: { item in
                Text(LocalizedKey("codes.delete.message", item.account.title))
            }
        }
    }
}

private extension TwoFactorView {
    /// The toolbar's buttons.
    ///
    /// Mac: Add after the title, then Import, Refresh and Lock at the far right.
    /// iOS: Import and Add (Lock comes from `barkToolbar`).
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) { LockToolbarButton() }
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { addButton }
        ToolbarSpacer(.flexible, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            importButton
            Button("global.refresh", systemImage: DesignKit.Icon.refresh) {
                hapticTaps += 1
                Task { await viewModel.refresh(auth: auth) }
            }
            .keyboardShortcut("r")
        }
        #else
        ToolbarItem(placement: .primaryAction) { importButton }
        ToolbarItem(placement: .primaryAction) { addButton }
        #endif
    }

    /// Opens the file picker for a 2FA export (one `otpauth://` link per line).
    var importButton: some View {
        Button("codes.import.button", systemImage: DesignKit.Icon.importFile, action: pickImportFile)
            .disabled(!viewModel.hasLoaded || subscriptions.isReadOnly)
    }

    /// Shows the file picker.
    func pickImportFile() {
        hapticTaps += 1
        isPickingImportFile = true
    }

    /// Reads the picked file in memory and asks to confirm the new accounts.
    func importFilePicked(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            importMessage = Localized("import.error.unreadable")
            return
        }
        let parsed = OTPAuthParser.parseLines(text)
        guard !parsed.accounts.isEmpty else {
            importMessage = Localized("codes.import.error.empty")
            return
        }
        let accounts = viewModel.newAccounts(in: parsed.accounts)
        importPlan = TwoFactorImportPlan(
            accounts: accounts,
            duplicateCount: parsed.accounts.count - accounts.count,
            failedLines: parsed.failedLines
        )
    }

    /// Encrypts and uploads the plan's accounts, then says how many were added.
    func runImport(_ plan: TwoFactorImportPlan) {
        Task {
            do {
                let added = try await viewModel.add(plan.accounts, auth: auth)
                importMessage = Localized("codes.import.done", added)
            } catch {
                importMessage = error.muninDescription
            }
        }
    }

    /// Opens the Add Account sheet (⌘N). Disabled until the accounts have loaded.
    var addButton: some View {
        Button("codes.add", systemImage: DesignKit.Icon.add) {
            hapticTaps += 1
            isAdding = true
        }
        .disabled(!viewModel.hasLoaded || subscriptions.isReadOnly)
        .keyboardShortcut("n")
    }
}

/// Accounts from an import file that aren't in Munin yet, waiting for confirmation.
private struct TwoFactorImportPlan: Identifiable {
    let id = UUID()
    /// The accounts to add.
    let accounts: [OTPAccount]
    /// How many were already in Munin, or repeated in the file.
    let duplicateCount: Int
    /// How many lines weren't a 2FA link.
    let failedLines: Int
}

/// The codes: Mac, a bordered table like the vault; iOS, a list (tap a row to copy).
///
/// Its own view, so the 2FA screen's chrome doesn't re-evaluate with it. The
/// Mac table has no selection, so rows aren't selectable; right-click a cell
/// for its menu.
private struct TwoFactorList: View {
    /// Read-only without a subscription: Delete is disabled.
    @Environment(SubscriptionManager.self) private var subscriptions

    /// The accounts to show.
    let viewModel: TwoFactorViewModel
    /// The screen's clock, passed to every row.
    let clock: TwoFactorClock
    /// Set by a row's Delete action, to ask for confirmation.
    @Binding var pendingDeletion: VaultItem?

    var body: some View {
        List {
            ForEach(viewModel.items) { item in
                TwoFactorRow(account: item.account, clock: clock)
                    .contextMenu {
                        Button("global.delete", systemImage: DesignKit.Icon.delete, role: .destructive) { pendingDeletion = item }
                            .disabled(subscriptions.isReadOnly)
                        Button("codes.copyCode", systemImage: DesignKit.Icon.copy) { TwoFactorRow.copyCode(of: item.account) }
                    }
            }
            if viewModel.undecryptableCount > 0 {
                Section {
                    undecryptableLabel
                }
            }
        }
        .listStyle(.plain)
    }

    /// A Mac cell's context menu: Copy Code and Delete.
    @ViewBuilder
    private func codeMenu(for item: VaultItem) -> some View {
        Button("codes.copyCode", systemImage: DesignKit.Icon.copy) { TwoFactorRow.copyCode(of: item.account) }
        Divider()
        Button("global.delete", systemImage: DesignKit.Icon.delete, role: .destructive) { pendingDeletion = item }
            .disabled(subscriptions.isReadOnly)
    }

    /// Says how many entries couldn't be decrypted with this vault key.
    private var undecryptableLabel: some View {
        Label(LocalizedKey("codes.undecryptable", viewModel.undecryptableCount), systemImage: DesignKit.Icon.undecryptable)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// Error, empty and loading states for the codes list.
private struct TwoFactorEmptyState: View {
    /// A load error to show, if the list is empty because loading failed.
    let errorMessage: String?
    /// Whether there are no accounts.
    let isEmpty: Bool
    /// Whether the first load has finished; before that a spinner shows.
    let hasLoaded: Bool
    /// Called by Try Again.
    let onRetry: () -> Void
    /// Called by the empty state's Add button.
    let onAdd: () -> Void

    var body: some View {
        if let errorMessage {
            ContentUnavailableView {
                Label("errors.loadVault.title", systemImage: DesignKit.Icon.offline)
            } description: {
                Text(errorMessage)
            } actions: {
                Button("global.tryAgain", action: onRetry)
            }
        } else if isEmpty {
            if hasLoaded {
                ContentUnavailableView {
                    Label("codes.empty.title", systemImage: DesignKit.Icon.noAccounts)
                } description: {
                    Text("codes.empty.message")
                } actions: {
                    Button("codes.empty.add", action: onAdd)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
    }
}
