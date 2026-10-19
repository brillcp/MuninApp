#if os(macOS)
import AppKit
import SwiftUI

/// The Munin window in the Mac menu bar: the password list. Click a row to
/// copy its password (cleared from the clipboard after a minute, as in the app).
struct MenuBarContent: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @Environment(VaultViewModel.self) private var vaultModel
    @Environment(\.openWindow) private var openWindow

    @State private var query = ""
    @State private var copiedID: PasswordItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            if session.state == .unlocked {
                TextField("vault.search.prompt", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
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
        .task(id: session.state) {
            if session.state == .unlocked, !vaultModel.hasLoaded {
                await vaultModel.refresh(auth: auth)
            }
        }
    }

    private var passwordList: some View {
        List(filteredItems) { item in
            Button { copy(item) } label: {
                HStack(spacing: 10) {
                    WebsiteIcon(url: item.url, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .lineLimit(1)
                        Text(item.username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if copiedID == item.id {
                        Text("global.copied")
                            .font(.caption)
                            .foregroundStyle(.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        .padding(10)
    }

    private var filteredItems: [PasswordItem] {
        let sorted = vaultModel.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.username.localizedCaseInsensitiveContains(trimmed)
                || $0.url.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func copy(_ item: PasswordItem) {
        Task { await vaultModel.copyPassword(item, auth: auth) }
        copiedID = item.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == item.id { copiedID = nil }
        }
    }
}
#endif
