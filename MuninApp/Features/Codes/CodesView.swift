import SwiftUI

struct CodesView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel = CodesViewModel()
    @State private var isAdding = false
    @State private var isShowingRecoveryKey = false
    @State private var pendingDeletion: VaultItem?
    /// One clock for the whole list, ticking on whole seconds.
    @State private var now = Date.now

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.items) { item in
                    CodeRow(account: item.account, now: now)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = item }
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = item }
                        }
                }
                if viewModel.undecryptableCount > 0 {
                    Section {
                        Label("\(viewModel.undecryptableCount) entries couldn't be decrypted with this device's key.",
                              systemImage: "exclamationmark.lock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                CodesEmptyState(
                    errorMessage: viewModel.items.isEmpty ? viewModel.errorMessage : nil,
                    isEmpty: viewModel.items.isEmpty && viewModel.undecryptableCount == 0,
                    hasLoaded: viewModel.hasLoaded,
                    onRetry: { Task { await viewModel.refresh(auth: auth) } },
                    onAdd: { isAdding = true }
                )
            }
            .navigationTitle("Codes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { isAdding = true }
                        .disabled(!viewModel.hasLoaded)
                        .keyboardShortcut("n")
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    Menu("Account", systemImage: "person.crop.circle") {
                        if let email = auth.email {
                            Text(email)
                        }
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await viewModel.refresh(auth: auth) }
                        }
                        .keyboardShortcut("r")
                        Button("Show Recovery Key", systemImage: "key") { isShowingRecoveryKey = true }
                            .disabled(viewModel.recoveryKey == nil)
                        Divider()
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            auth.signOut()
                        }
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await viewModel.refresh(auth: auth) }
                    }
                    .keyboardShortcut("r")
                }
                #endif
            }
            .refreshable { await viewModel.refresh(auth: auth) }
            .task { await viewModel.refresh(auth: auth) }
            .task(tick)
            .sheet(isPresented: $isAdding) {
                AddAccountView { accounts in
                    try await viewModel.add(accounts, auth: auth)
                }
            }
            .sheet(isPresented: $isShowingRecoveryKey) {
                RecoveryKeyView(recoveryKey: viewModel.recoveryKey ?? "")
            }
            .confirmationDialog("Delete Account?", item: $pendingDeletion, titleVisibility: .visible) { item in
                Button("Delete \(item.account.title)", role: .destructive) {
                    Task { await viewModel.delete(item, auth: auth) }
                }
            } message: { item in
                Text("Make sure 2FA is turned off for \(item.account.title), or you have another way to sign in. This can't be undone.")
            }
        }
        .tint(.mint)
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
                Label("Couldn't load your vault", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again", action: onRetry)
            }
        } else if isEmpty {
            if hasLoaded {
                ContentUnavailableView {
                    Label("No accounts yet", systemImage: "lock.shield")
                } description: {
                    Text("Scan a 2FA QR code or import from Google Authenticator.")
                } actions: {
                    Button("Add Account", action: onAdd)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
    }
}

#Preview {
    CodesView()
        .environment(AuthManager())
}
