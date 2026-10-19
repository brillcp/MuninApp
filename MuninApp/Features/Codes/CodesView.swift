import SwiftUI

struct CodesView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: CodesViewModel
    @State private var isAdding = false
    @State private var pendingDeletion: VaultItem?
    /// One clock for the whole list, ticking on whole seconds.
    @State private var now = Date.now

    init(session: VaultSession) {
        _viewModel = State(initialValue: CodesViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            codesList
            .overlay {
                CodesEmptyState(
                    errorMessage: viewModel.items.isEmpty ? viewModel.errorMessage : nil,
                    isEmpty: viewModel.items.isEmpty && viewModel.undecryptableCount == 0,
                    hasLoaded: viewModel.hasLoaded,
                    onRetry: { Task { await viewModel.refresh(auth: auth) } },
                    onAdd: { isAdding = true }
                )
            }
            .navigationTitle("codes.title")
            .navigationSplitViewStyle(.prominentDetail)
            .barkToolbar(title: "codes.title")
            .toolbar { toolbarContent }
            .refreshable { await viewModel.refresh(auth: auth) }
            .task { await viewModel.refresh(auth: auth) }
            .task(tick)
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

    /// Mac: a bordered table like the vault. iOS: a list; tap a row to copy.
    @ViewBuilder
    private var codesList: some View {
        #if os(macOS)
        // No selection: rows aren't selectable. Right-click a cell for its menu.
        Table(viewModel.items) {
            TableColumn("codes.column.account") { item in
                AccountLabel(title: item.account.title, subtitle: item.account.subtitle)
                    .equatable()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu { codeMenu(for: item) }
            }
            TableColumn("codes.column.code") { item in
                CodeCell(account: item.account, now: now)
                    .contextMenu { codeMenu(for: item) }
            }
        }
        .tableStyle(.bordered)
        .safeAreaInset(edge: .bottom) {
            if viewModel.undecryptableCount > 0 {
                undecryptableLabel
                    .padding(8)
            }
        }
        #else
        List {
            ForEach(viewModel.items) { item in
                CodeRow(account: item.account, now: now)
                    .contextMenu {
                        Button("global.delete", systemImage: "trash", role: .destructive) { pendingDeletion = item }
                    }
                    .swipeActions {
                        Button("global.delete", systemImage: "trash", role: .destructive) { pendingDeletion = item }
                    }
            }
            if viewModel.undecryptableCount > 0 {
                Section {
                    undecryptableLabel
                }
            }
        }
        .listStyle(.plain)
        #endif
    }

    @ViewBuilder
    private func codeMenu(for item: VaultItem) -> some View {
        Button("codes.copyCode", systemImage: "doc.on.doc") { CodeRow.copyCode(of: item.account) }
        Divider()
        Button("global.delete", systemImage: "trash", role: .destructive) { pendingDeletion = item }
    }

    private var undecryptableLabel: some View {
        Label(LocalizedKey("codes.undecryptable", viewModel.undecryptableCount), systemImage: "exclamationmark.lock")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button("global.refresh", systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh(auth: auth) }
            }
            .keyboardShortcut("r")
        }
        #endif
        ToolbarItem(placement: .primaryAction) {
            Button("codes.add", systemImage: "plus") { isAdding = true }
                .disabled(!viewModel.hasLoaded)
                .keyboardShortcut("n")
        }
    }

    private func tick() async {
        while !Task.isCancelled {
            let fraction = Date.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
            try? await Task.sleep(for: .seconds(1 - fraction))
            now = .now
        }
    }

}

/// Error, empty and loading states for the codes list.
private struct CodesEmptyState: View {
    let errorMessage: String?
    let isEmpty: Bool
    let hasLoaded: Bool
    let onRetry: () -> Void
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
    CodesView(session: VaultSession())
        .environment(AuthManager())
        .environment(VaultSession())
}
