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
            .overlay { emptyState }
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
            .confirmationDialog(
                "Delete \(pendingDeletion?.account.title ?? "account")?",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let item = pendingDeletion {
                        Task { await viewModel.delete(item, auth: auth) }
                    }
                    pendingDeletion = nil
                }
            } message: {
                Text("Make sure 2FA is turned off for this account, or you have another way to sign in. This can't be undone.")
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

    @ViewBuilder
    private var emptyState: some View {
        if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load your vault", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await viewModel.refresh(auth: auth) } }
            }
        } else if viewModel.items.isEmpty && viewModel.undecryptableCount == 0 {
            if viewModel.hasLoaded {
                ContentUnavailableView {
                    Label("No accounts yet", systemImage: "lock.shield")
                } description: {
                    Text("Scan a 2FA QR code or import from Google Authenticator.")
                } actions: {
                    Button("Add Account") { isAdding = true }
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
