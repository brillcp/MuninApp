#if os(iOS)
import SwiftUI

/// iOS search tab: passwords and 2FA codes in one list, in two sections.
///
/// Nothing is remembered between searches. Both lists load on appear in case
/// their tabs haven't been opened yet. The `.searchable` modifier sits on the
/// NavigationStack (not inside it), as in Apple's search tab examples, so the
/// tab bar can turn the Search tab into its own search field.
struct SearchView: View {
    @Environment(AuthManager.self) private var auth
    /// The search field's text.
    @State private var query = ""
    /// Matching passwords. Filtered once per change of query or data, not on every body evaluation.
    @State private var passwords: [PasswordItem] = []
    /// Matching 2FA accounts, filtered the same way.
    @State private var codes: [VaultItem] = []
    /// One clock for the code rows.
    @State private var clock = TwoFactorClock()

    /// The passwords to search.
    let vaultModel: VaultViewModel
    /// The 2FA accounts to search.
    let twoFactorModel: TwoFactorViewModel
    /// Tapping a password opens it in the Vault tab.
    let onOpenPassword: (PasswordItem) -> Void

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
                            TwoFactorRow(account: item.account, clock: clock)
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
            .task {
                if !vaultModel.hasLoaded { await vaultModel.refresh(auth: auth) }
                if !twoFactorModel.hasLoaded { await twoFactorModel.refresh(auth: auth) }
            }
            .task(clock.run)
        }
        .searchable(text: $query, prompt: "search.prompt")
        .onChange(of: query, initial: true) { updateResults() }
        .onChange(of: vaultModel.items) { updateResults() }
        .onChange(of: twoFactorModel.items) { updateResults() }
    }
}

private extension SearchView {
    /// The query without surrounding spaces.
    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// Filters passwords (name, username, URL) and 2FA accounts (title,
    /// subtitle) by the query. An empty query shows nothing.
    func updateResults() {
        guard !trimmedQuery.isEmpty else {
            passwords = []
            codes = []
            return
        }
        passwords = vaultModel.items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.username.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.url.localizedCaseInsensitiveContains(trimmedQuery)
        }
        codes = twoFactorModel.items.filter {
            $0.account.title.localizedCaseInsensitiveContains(trimmedQuery)
                || ($0.account.subtitle?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }
}

/// A password result: icon, name, username and a disclosure chevron.
private struct SearchPasswordRow: View {
    /// The password item.
    let item: PasswordItem

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            WebsiteIcon(url: item.url)
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
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
