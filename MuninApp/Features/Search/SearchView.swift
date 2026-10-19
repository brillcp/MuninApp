#if os(iOS)
import SwiftUI

/// iOS search tab: passwords and 2FA codes in one list, in two sections.
/// Nothing is remembered between searches.
struct SearchView: View {
    let vaultModel: VaultViewModel
    let codesModel: CodesViewModel
    /// Tapping a password opens it in the Vault tab.
    let onOpenPassword: (PasswordItem) -> Void

    @Environment(AuthManager.self) private var auth
    @State private var query = ""
    /// One clock for the code rows.
    @State private var clock = CodeClock()

    var body: some View {
        NavigationStack {
            List {
                if !passwords.isEmpty {
                    Section("search.section.passwords") {
                        ForEach(passwords) { item in
                            Button { onOpenPassword(item) } label: {
                                SearchPasswordRow(item: item)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                if !codes.isEmpty {
                    Section("search.section.codes") {
                        ForEach(codes) { item in
                            CodeRow(account: item.account, clock: clock)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView("search.empty.title", systemImage: "magnifyingglass", description: Text("search.empty.message"))
                } else if passwords.isEmpty && codes.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .navigationTitle("search.title")
            .barkNavigationBar()
            .task {
                // The other tabs may not have loaded yet.
                if !vaultModel.hasLoaded { await vaultModel.refresh(auth: auth) }
                if !codesModel.hasLoaded { await codesModel.refresh(auth: auth) }
            }
            .task { await clock.run() }
        }
        // On the NavigationStack (not inside it), as Apple's search-tab examples do,
        // so the tab bar can turn the Search tab into its own search field.
        .searchable(text: $query, prompt: "search.prompt")
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var passwords: [PasswordItem] {
        guard !trimmedQuery.isEmpty else { return [] }
        return vaultModel.items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.username.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.url.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var codes: [VaultItem] {
        guard !trimmedQuery.isEmpty else { return [] }
        return codesModel.items.filter {
            $0.account.title.localizedCaseInsensitiveContains(trimmedQuery)
                || ($0.account.subtitle?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

}

private struct SearchPasswordRow: View {
    let item: PasswordItem

    var body: some View {
        HStack(spacing: 12) {
            WebsiteIcon(url: item.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.username)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}
#endif
