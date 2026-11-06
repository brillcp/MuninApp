#if os(macOS)
import AppKit
import SwiftUI

/// The menu bar extra's content: a searchable list of passwords.
///
/// Each row has Copy Username and Copy Password buttons. A copied password is
/// cleared from the clipboard after a minute. While the vault is locked, the
/// view shows only a locked state.
struct MenuBarContent: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(VaultViewModel.self) private var vaultModel
    @Environment(\.openWindow) private var openWindow

    @State private var query = ""
    /// The items to show, sorted and filtered.
    ///
    /// Updated when the query or items change instead of on every render.
    @State private var filteredItems: [PasswordItem] = []
    /// The most recently copied field, used to show a brief Copied label.
    @State private var copied: CopiedField?

    var body: some View {
        VStack(spacing: DesignKit.Spacing.Primitive.s0) {
            if session.state == .unlocked {
                TextField("vault.search.prompt", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(DesignKit.Spacing.Primitive.s12)
                Divider()
                passwordList
            } else {
                ContentUnavailableView("lock.title", systemImage: DesignKit.Icon.lock)
                    .frame(maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 320, height: 420)
        .tint(.primary)
        .onChange(of: query, initial: true) { updateFilteredItems() }
        .onChange(of: vaultModel.items) { updateFilteredItems() }
        .task(id: session.state) {
            if session.state == .unlocked, !vaultModel.hasLoaded {
                await vaultModel.refresh(auth: auth)
            }
        }
    }
}

private extension MenuBarContent {
    /// A field copied from a specific row.
    struct CopiedField: Equatable {
        /// The identifier of the row's item.
        let id: PasswordItem.ID
        let field: MenuBarPasswordRow.Field
    }

    /// The filtered passwords, with a spinner while loading and an empty state
    /// when nothing matches.
    var passwordList: some View {
        List(filteredItems) { item in
            MenuBarPasswordRow(
                item: item,
                copiedField: copied?.id == item.id ? copied?.field : nil,
                onCopyUsername: { copyUsername(item) },
                onCopyPassword: { copyPassword(item) }
            )
            .listRowSeparatorTint(.secondary)
        }
        .listStyle(.sidebar)
        .overlay {
            if !vaultModel.hasLoaded {
                ProgressView()
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    /// The footer with Open, Lock (while unlocked), and Quit buttons.
    var footer: some View {
        HStack {
            Button("menuBar.open") {
                openWindow(id: MyApp.mainWindowID)
                NSApp.activate()
            }
            Spacer()
            if session.state == .unlocked {
                Button("lock.command", systemImage: DesignKit.Icon.lock, action: session.lock)
                    .labelStyle(.iconOnly)
                    .help(Text("lock.command"))
            }
            Button("menuBar.quit", systemImage: DesignKit.Icon.quit) { NSApp.terminate(nil) }
                .labelStyle(.iconOnly)
                .help(Text("menuBar.quit"))
        }
        .buttonStyle(.borderless)
        .padding(DesignKit.Spacing.Primitive.s12)
    }

    /// Sorts the vault's items by name, filters them by name, username, or URL,
    /// and stores the result in `filteredItems`.
    func updateFilteredItems() {
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

    /// Copies the item's username and shows Copied on its row.
    func copyUsername(_ item: PasswordItem) {
        Pasteboard.copy(item.username)
        showCopied(CopiedField(id: item.id, field: .username))
    }

    /// Decrypts and copies the item's password, and shows Copied on its row.
    ///
    /// The password is cleared from the clipboard after a minute.
    func copyPassword(_ item: PasswordItem) {
        Task { await vaultModel.copyPassword(item, auth: auth) }
        showCopied(CopiedField(id: item.id, field: .password))
    }

    /// Shows the Copied label for a field, then hides it after a moment unless
    /// another field is copied first.
    func showCopied(_ field: CopiedField) {
        copied = field
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copied == field { copied = nil }
        }
    }
}

/// A row in the menu bar list showing a password's icon, name, username, and
/// copy buttons.
private struct MenuBarPasswordRow: View {
    let item: PasswordItem
    /// The field just copied from this row, if any.
    let copiedField: Field?
    let onCopyUsername: () -> Void
    let onCopyPassword: () -> Void

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            WebsiteIcon(url: item.url, size: DesignKit.Spacing.Primitive.s24)
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
                Text(item.name)
                    .lineLimit(1)
                if !item.username.isEmpty {
                    Text(item.username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if copiedField != nil {
                Text("global.copied")
                    .font(.caption)
                    .foregroundStyle(.accent)
            }
            Button("menuBar.copyUsername", systemImage: DesignKit.Icon.username, action: onCopyUsername)
                .help(Text("menuBar.copyUsername"))
                .disabled(item.username.isEmpty)
            Button("vault.copyPassword", systemImage: DesignKit.Icon.password, action: onCopyPassword)
                .help(Text("vault.copyPassword"))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(height: DesignKit.Spacing.Primitive.s48)
    }
}

private extension MenuBarPasswordRow {
    /// A field that can be copied from the row.
    enum Field { case username, password }
}
#endif
