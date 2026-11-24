#if os(iOS)
import SwiftUI

/// A view that searches passwords, two-factor accounts, and cards in a single
/// list on iOS.
///
/// Selecting a password or a card opens it in this view's own navigation
/// stack, where it can be edited or deleted without affecting its tab.
///
/// Results aren't kept between searches. Every data source loads on appear in
/// case their tabs haven't been opened yet. The `searchable` modifier is
/// applied to the `NavigationStack` rather than its content, so the tab bar can
/// turn the Search tab into a search field.
struct SearchView: View {
    /// The search text.
    @State private var query = ""
    /// The passwords matching the query.
    ///
    /// Filtered when the query or data changes, rather than on every body evaluation.
    @State private var passwords: [PasswordItem] = []
    /// The two-factor accounts matching the query.
    @State private var codes: [VaultItem] = []
    /// The cards matching the query.
    @State private var cards: [CardItem] = []
    /// The clock shared by all code rows.
    @State private var clock = TwoFactorClock()

    /// The passwords to search.
    let vaultModel: VaultViewModel
    /// The two-factor accounts to search.
    let twoFactorModel: TwoFactorViewModel
    /// The cards to search.
    let cardsModel: CardsViewModel

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
                if !cards.isEmpty {
                    Section("search.section.cards") {
                        ForEach(cards) { item in
                            NavigationLink(value: CardRoute(id: item.id)) {
                                CardRow(item: item)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView("search.empty.title", systemImage: DesignKit.Icon.search, description: Text("search.empty.message"))
                } else if passwords.isEmpty && codes.isEmpty && cards.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
            .navigationTitle("search.title")
            .navigationDestination(for: PasswordItem.ID.self) { id in
                PasswordDetail(item: vaultModel.items.first { $0.id == id }, viewModel: vaultModel, dismissesWhenDeleted: true)
            }
            .navigationDestination(for: CardRoute.self) { route in
                CardDetail(item: cardsModel.items.first { $0.id == route.id }, viewModel: cardsModel, dismissesWhenDeleted: true)
            }
            .task {
                if !vaultModel.hasLoaded { await vaultModel.refresh() }
                if !twoFactorModel.hasLoaded { await twoFactorModel.refresh() }
                if !cardsModel.hasLoaded { await cardsModel.refresh() }
            }
            .task(clock.run)
        }
        .searchable(text: $query, prompt: "search.prompt")
        .onChange(of: query, initial: true) { updateResults() }
        .onChange(of: vaultModel.items) { updateResults() }
        .onChange(of: twoFactorModel.items) { updateResults() }
        .onChange(of: cardsModel.items) { updateResults() }
    }
}

private extension SearchView {
    /// A card opened from the results.
    ///
    /// A separate type, so it doesn't collide with the passwords' `UUID`
    /// navigation values.
    struct CardRoute: Hashable {
        /// The card's identifier.
        let id: UUID
    }

    /// The search text without leading and trailing spaces.
    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// Filters passwords, two-factor accounts, and cards by the query.
    ///
    /// Passwords match on name, username, or URL; accounts match on title or
    /// subtitle; cards match on name or cardholder. An empty query clears the
    /// results.
    func updateResults() {
        guard !trimmedQuery.isEmpty else {
            passwords = []
            codes = []
            cards = []
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
        cards = cardsModel.items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.holder.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}
#endif
