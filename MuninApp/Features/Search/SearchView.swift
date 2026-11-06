#if os(iOS)
import SwiftUI

/// A view that searches passwords and two-factor accounts in a single list on iOS.
///
/// Selecting a password opens it in this view's own navigation stack, where it
/// can be edited or deleted without affecting the Vault tab.
///
/// Results aren't kept between searches. Both data sources load on appear in
/// case their tabs haven't been opened yet. The `searchable` modifier is
/// applied to the `NavigationStack` rather than its content, so the tab bar can
/// turn the Search tab into a search field.
struct SearchView: View {
    @Environment(AuthManager.self) private var auth
    @State private var query = ""
    /// The passwords matching the query.
    ///
    /// Filtered when the query or data changes, rather than on every body evaluation.
    @State private var passwords: [PasswordItem] = []
    /// The two-factor accounts matching the query.
    @State private var codes: [VaultItem] = []
    /// The clock shared by all code rows.
    @State private var clock = TwoFactorClock()

    /// The passwords to search.
    let vaultModel: VaultViewModel
    /// The two-factor accounts to search.
    let twoFactorModel: TwoFactorViewModel

    var body: some View {
        NavigationStack {
            List {
                if !passwords.isEmpty {
                    Section("search.section.passwords") {
                        ForEach(passwords) { item in
                            NavigationLink(value: item.id) {
                                PasswordTitleCell(item: item)
                            }
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
            #if os(macOS)
            .alternatingRowBackgrounds()
            #endif
            .listStyle(.plain)
            .overlay {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView("search.empty.title", systemImage: DesignKit.Icon.search, description: Text("search.empty.message"))
                } else if passwords.isEmpty && codes.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .navigationTitle("search.title")
            .navigationDestination(for: PasswordItem.ID.self) { id in
                PasswordDetail(item: vaultModel.items.first { $0.id == id }, viewModel: vaultModel, dismissesWhenDeleted: true)
            }
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
    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// Filters passwords and two-factor accounts by the query.
    ///
    /// Passwords match on name, username, or URL; accounts match on title or
    /// subtitle. An empty query clears the results.
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
#endif
