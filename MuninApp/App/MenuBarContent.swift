#if os(macOS)
import AppKit
import SwiftUI

/// The Munin window in the Mac menu bar: the password list. Each row has
/// Copy Username and Copy Password (the password clears from the clipboard
/// after a minute, as in the app).
struct MenuBarContent: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(VaultViewModel.self) private var vaultModel
    @Environment(\.openWindow) private var openWindow

    @State private var query = ""
    /// Sorted and filtered once per change of query or data.
    @State private var filteredItems: [PasswordItem] = []
    /// The row and field just copied, for the short "Copied" label.
    @State private var copied: CopiedField?

    private struct CopiedField: Equatable {
        let id: PasswordItem.ID
        let field: MenuBarPasswordRow.Field
    }

    var body: some View {
        VStack(spacing: DesignKit.Spacing.Primitive.s0) {
            if session.state == .unlocked {
                TextField("vault.search.prompt", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(DesignKit.Spacing.Primitive.s12)
                Divider()
                passwordList
            } else {
                ContentUnavailableView("lock.title", systemImage: "lock")
                    .frame(maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 320, height: 420)
        .onChange(of: query, initial: true) { updateFilteredItems() }
        .onChange(of: vaultModel.items) { updateFilteredItems() }
        .task(id: session.state) {
            if session.state == .unlocked, !vaultModel.hasLoaded {
                await vaultModel.refresh(auth: auth)
            }
        }
    }

    private var passwordList: some View {
        List(filteredItems) { item in
            MenuBarPasswordRow(
                item: item,
                copiedField: copied?.id == item.id ? copied?.field : nil,
                onCopyUsername: { copyUsername(item) },
                onCopyPassword: { copyPassword(item) }
            )
        }
        .listStyle(.plain)
        .overlay {
            if !vaultModel.hasLoaded {
                ProgressView()
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("menuBar.open") {
                openWindow(id: MyApp.mainWindowID)
                NSApp.activate()
            }
            Spacer()
            if session.state == .unlocked {
                Button("lock.command", systemImage: "lock") { session.lock() }
                    .labelStyle(.iconOnly)
                    .help(Text("lock.command"))
            }
            Button("menuBar.quit", systemImage: "power") { NSApp.terminate(nil) }
                .labelStyle(.iconOnly)
                .help(Text("menuBar.quit"))
        }
        .buttonStyle(.borderless)
        .padding(DesignKit.Spacing.Primitive.s12)
    }

    private func updateFilteredItems() {
        let sorted = vaultModel.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            filteredItems = sorted
            return
        }
        filteredItems = sorted.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.username.localizedCaseInsensitiveContains(trimmed)
                || $0.url.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func copyUsername(_ item: PasswordItem) {
        Pasteboard.copy(item.username)
        showCopied(CopiedField(id: item.id, field: .username))
    }

    private func copyPassword(_ item: PasswordItem) {
        Task { await vaultModel.copyPassword(item, auth: auth) }
        showCopied(CopiedField(id: item.id, field: .password))
    }

    private func showCopied(_ field: CopiedField) {
        copied = field
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copied == field { copied = nil }
        }
    }
}

/// One password in the menu bar list: icon, name, username, and two copy buttons.
private struct MenuBarPasswordRow: View {
    enum Field { case username, password }

    let item: PasswordItem
    /// Which field was just copied from this row, if any.
    let copiedField: Field?
    let onCopyUsername: () -> Void
    let onCopyPassword: () -> Void

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            WebsiteIcon(url: item.url, size: 24)
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.username)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if copiedField != nil {
                Text("global.copied")
                    .font(.caption)
                    .foregroundStyle(.accent)
            }
            Button("menuBar.copyUsername", systemImage: "person", action: onCopyUsername)
                .help(Text("menuBar.copyUsername"))
                .disabled(item.username.isEmpty)
            Button("vault.copyPassword", systemImage: "key", action: onCopyPassword)
                .help(Text("vault.copyPassword"))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}
#endif
