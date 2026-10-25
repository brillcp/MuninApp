import SwiftUI

/// The 2FA screen: every account's current code, with add, refresh and delete.
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
                if subscriptions.isReadOnly { ReadOnlyBanner() }
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
    /// Mac: Add after the title, then Refresh and Lock at the far right.
    /// iOS: Add (Lock comes from `barkToolbar`).
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation, content: LockToolbarButton.init)
        ToolbarItem(placement: .primaryAction) { addButton }
        ToolbarSpacer(.flexible, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button("global.refresh", systemImage: "arrow.clockwise") {
                hapticTaps += 1
                Task { await viewModel.refresh(auth: auth) }
            }
            .keyboardShortcut("r")
        }
        #else
        ToolbarItem(placement: .primaryAction) { addButton }
        #endif
    }

    /// Opens the Add Account sheet (⌘N). Disabled until the accounts have loaded.
    var addButton: some View {
        Button("codes.add", systemImage: "plus") {
            hapticTaps += 1
            isAdding = true
        }
        .disabled(!viewModel.hasLoaded || subscriptions.isReadOnly)
        .keyboardShortcut("n")
    }
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
                        Button("global.delete", systemImage: "trash", role: .destructive) { pendingDeletion = item }
                            .disabled(subscriptions.isReadOnly)
                        Button("global.copy", systemImage: "square.on.square", role: .confirm) { pendingDeletion = item }
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
        Button("codes.copyCode", systemImage: "square.on.square") { TwoFactorRow.copyCode(of: item.account) }
        Divider()
        Button("global.delete", systemImage: "trash", role: .destructive) { pendingDeletion = item }
            .disabled(subscriptions.isReadOnly)
    }

    /// Says how many entries couldn't be decrypted with this vault key.
    private var undecryptableLabel: some View {
        Label(LocalizedKey("codes.undecryptable", viewModel.undecryptableCount), systemImage: "exclamationmark.lock")
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
                Label("errors.loadVault.title", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("global.tryAgain", action: onRetry)
            }
        } else if isEmpty {
            if hasLoaded {
                ContentUnavailableView {
                    Label("codes.empty.title", systemImage: "lock.shield")
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

#Preview {
    TwoFactorView(viewModel: TwoFactorViewModel(session: VaultSession()))
        .environment(AuthManager())
        .environment(VaultSession())
        .environment(SubscriptionManager())
}
