import SwiftUI
import UniformTypeIdentifiers

/// A view that lists two-factor accounts with their current codes.
///
/// Supports adding, importing, refreshing, and deleting accounts.
struct TwoFactorView: View {
    /// The subscription state. Without an active subscription, the vault is
    /// read-only.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// A Boolean value that indicates whether the Add Account sheet is presented.
    @State private var isAdding = false
    /// The account waiting for delete confirmation.
    @State private var pendingDeletion: VaultItem?
    /// A counter incremented by toolbar buttons to trigger a light haptic.
    @State private var hapticTaps = 0
    /// The clock shared by all code rows.
    @State private var clock = TwoFactorClock()
    @State private var isPickingImportFile = false
    /// The parsed import awaiting confirmation.
    @State private var importPlan: TwoFactorImportPlan?
    /// The result of an import: the number of accounts added, or why the file
    /// couldn't be read.
    @State private var importMessage: String?

    /// The view model that loads, adds, and deletes accounts.
    let viewModel: TwoFactorViewModel

    var body: some View {
        NavigationStack {
            TwoFactorList(viewModel: viewModel, clock: clock, pendingDeletion: $pendingDeletion)
                .overlay {
                    TwoFactorEmptyState(
                        errorMessage: viewModel.items.isEmpty ? viewModel.errorMessage : nil,
                        isEmpty: viewModel.items.isEmpty && viewModel.undecryptableCount == 0,
                        hasLoaded: viewModel.hasLoaded,
                        onRetry: { Task { await viewModel.refresh() } },
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
                .refreshable { await viewModel.refresh() }
                .task { await viewModel.refresh() }
                .task(clock.run)
                .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
                .sheet(isPresented: $isAdding) {
                    AddAccountView { accounts in
                        try await viewModel.add(accounts)
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
                        Task { await viewModel.delete(item) }
                    }
                } message: { item in
                    Text(LocalizedKey("codes.delete.message", item.account.title))
                }
        }
    }
}

private extension TwoFactorView {
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
                Task { await viewModel.refresh() }
            }
            .keyboardShortcut("r")
        }
        #else
        ToolbarItem(placement: .primaryAction) { addButton }
        ToolbarItem(placement: .secondaryAction) { importButton }
        #endif
    }

    /// A button that opens the file picker for a 2FA export with one
    /// `otpauth://` URL per line.
    var importButton: some View {
        Button("codes.import.button", systemImage: DesignKit.Icon.importFile, action: pickImportFile)
            .disabled(!viewModel.hasLoaded || subscriptions.isReadOnly)
    }

    func pickImportFile() {
        hapticTaps += 1
        isPickingImportFile = true
    }

    /// Reads the selected file and asks the user to confirm the new accounts.
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

    /// Encrypts and uploads the plan's accounts, then reports how many were added.
    func runImport(_ plan: TwoFactorImportPlan) {
        Task {
            do {
                let added = try await viewModel.add(plan.accounts)
                importMessage = Localized("codes.import.done", added)
            } catch {
                importMessage = error.muninDescription
            }
        }
    }

    /// A button that opens the Add Account sheet (⌘N).
    ///
    /// Disabled until accounts have loaded, and while the vault is read-only.
    var addButton: some View {
        Button("codes.add", systemImage: DesignKit.Icon.add) {
            hapticTaps += 1
            isAdding = true
        }
        .buttonStyle(.glassProminent)
        .disabled(!viewModel.hasLoaded || subscriptions.isReadOnly)
        .keyboardShortcut("n")
    }
}

/// Accounts from an import file that aren't in the vault yet, awaiting
/// confirmation.
private struct TwoFactorImportPlan: Identifiable {
    let id = UUID()
    let accounts: [OTPAccount]
    /// The number of accounts already in the vault or repeated in the file.
    let duplicateCount: Int
    /// The number of lines that aren't valid 2FA URLs.
    let failedLines: Int
}
