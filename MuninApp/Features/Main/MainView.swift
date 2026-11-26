import SwiftUI

/// The root view of the unlocked app, with a sidebar on macOS and iPad and a
/// tab bar on iPhone.
///
/// The main section holds the vault, 2FA, and cards tabs. On iOS, Settings and Search
/// are tabs too; on macOS, the sidebar is a fixed ``MainSidebar``, and
/// Settings is a separate window opened from the user's initials at its
/// bottom. On iOS, the Search tab sits at the trailing edge of the tab bar and
/// opens passwords in its own navigation stack.
struct MainView: View {
    /// The vault session, used to hold the AutoFill guide while a new recovery
    /// key is shown.
    @Environment(VaultSession.self) private var session
    /// The vault model shared by the vault, Search, and the macOS menu bar.
    @Environment(VaultViewModel.self) private var vaultModel
    /// The subscription state, used to show the paywall while the vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// The AutoFill setup state, used to present the setup guide.
    @Environment(AutoFillSetup.self) private var autoFill
    /// The 2FA model shared by the 2FA and Search tabs.
    @Environment(TwoFactorViewModel.self) private var twoFactorModel
    /// The cards model shared by the Cards and Search tabs.
    @Environment(CardsViewModel.self) private var cardsModel

    /// The selected section, which ⌘1, ⌘2, and ⌘3 also change on macOS.
    @State private var selection: Section = .vault
    /// Accounts from a 2FA setup link, awaiting confirmation.
    @State private var linkedAccounts: LinkedAccounts?
    /// The reason a 2FA setup link couldn't be added, shown in an alert.
    @State private var linkError: String?

    /// A 2FA setup link that opened the app, cleared once handled.
    @Binding var pendingCodeLink: URL?

    var body: some View {
        @Bindable var subscriptions = subscriptions
        @Bindable var vaultModel = vaultModel
        @Bindable var cardsModel = cardsModel
        @Bindable var autoFill = autoFill
        sections
            .task { await subscriptions.start() }
            .sheet(isPresented: $subscriptions.isPaywallPresented) {
                PaywallView()
            }
            .sheet(isPresented: $autoFill.isGuidePresented) {
                AutoFillSetupView()
            }
            .alert("vault.saveFailed.title", item: $vaultModel.failureMessage) { _ in
                Button("global.done") {}
            } message: { message in
                Text(message)
            }
            .alert("vault.saveFailed.title", item: $cardsModel.failureMessage) { _ in
                Button("global.done") {}
            } message: { message in
                Text(message)
            }
            .onChange(of: pendingCodeLink, initial: true, openPendingCodeLink)
            .onChange(of: canPresentAutoFillGuide, initial: true, presentAutoFillGuide)
            .confirmationDialog("codes.link.title", item: $linkedAccounts, titleVisibility: .visible) { linked in
                Button("codes.link.add") { addLinkedAccounts(linked.accounts) }
            } message: { linked in
                Text(LocalizedKey("codes.link.message", linked.accounts.map(\.title).joined(separator: ", ")))
            }
            .alert("codes.link.failed", item: $linkError) { _ in
                Button("global.done") {}
            } message: { message in
                Text(message)
            }
            #if os(macOS)
            .focusedSceneValue(\.mainSection, $selection)
            #endif
            #if os(iOS)
            .tabViewSearchActivation(.searchTabSelection)
            .scrollIndicators(.never)
            #endif
    }
}

extension MainView {
    /// The app's top-level tabs.
    enum Section: Hashable {
        /// The passwords.
        case vault
        /// The 2FA accounts.
        case twoFactor
        /// The stored cards.
        case cards
        /// Search, on iOS.
        case search
        /// Settings, on iOS.
        case settings
    }
}

private extension MainView {
    /// The sections and the way to switch between them.
    ///
    /// On macOS, a fixed ``MainSidebar`` floats on the leading edge and the
    /// selected section fills the window behind it, like the password panel.
    /// The lists inset their content by ``EnvironmentValues/sidebarWidth``.
    /// On iOS, it's a tab view that shows a sidebar on iPad and a tab bar on
    /// iPhone.
    @ViewBuilder
    var sections: some View {
        #if os(macOS)
        selectedSection
            .environment(\.sidebarWidth, MainSidebar.occupiedWidth)
            .overlay(alignment: .leading) {
                MainSidebar(selection: $selection)
            }
        #else
        TabView(selection: $selection) {
            TabSection("main.section.munin") {
                Tab(value: Section.vault) {
                    VaultView(viewModel: vaultModel, twoFactorModel: twoFactorModel)
                } label: {
                    SidebarTabLabel(title: "main.tab.vault", systemImage: DesignKit.Icon.vault, isSelected: selection == .vault)
                }
                Tab(value: Section.twoFactor) {
                    TwoFactorView(viewModel: twoFactorModel)
                } label: {
                    SidebarTabLabel(title: "main.tab.codes", systemImage: DesignKit.Icon.twoFactor, isSelected: selection == .twoFactor)
                }
                Tab(value: Section.cards) {
                    CardsView(viewModel: cardsModel)
                } label: {
                    SidebarTabLabel(title: "main.tab.cards", systemImage: DesignKit.Icon.cards, isSelected: selection == .cards)
                }
            }
            Tab("settings.title", systemImage: DesignKit.Icon.settings, value: Section.settings) {
                NavigationStack {
                    SettingsView()
                        .leadingNavigationTitle("settings.title")
                }
            }
            Tab(value: Section.search, role: .search) {
                SearchView(vaultModel: vaultModel, twoFactorModel: twoFactorModel, cardsModel: cardsModel)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #endif
    }

    #if os(macOS)
    /// The selected section's view.
    @ViewBuilder
    var selectedSection: some View {
        switch selection {
        case .twoFactor:
            TwoFactorView(viewModel: twoFactorModel)
        case .cards:
            CardsView(viewModel: cardsModel)
        default:
            VaultView(viewModel: vaultModel, twoFactorModel: twoFactorModel)
        }
    }
    #endif

    /// A Boolean value that indicates whether the AutoFill guide can open by
    /// itself: AutoFill's status is known, the subscription has loaded, and
    /// no other sheet is showing, such as the paywall or a new recovery key.
    var canPresentAutoFillGuide: Bool {
        autoFill.isEnabled != nil
            && subscriptions.status != nil
            && !subscriptions.isPaywallPresented
            && session.newRecoveryKey == nil
            && linkedAccounts == nil
    }

    /// Opens the AutoFill setup guide once, the first time it can.
    func presentAutoFillGuide() {
        guard canPresentAutoFillGuide else { return }
        autoFill.presentGuideIfNeeded()
    }

    /// Handles a pending 2FA setup link by switching to the 2FA tab and asking
    /// to add its accounts, or explaining why when the vault is read-only.
    func openPendingCodeLink() {
        guard let url = pendingCodeLink else { return }
        pendingCodeLink = nil
        selection = .twoFactor
        guard !subscriptions.isReadOnly else {
            linkError = Localized("errors.munin.subscriptionRequired")
            return
        }
        do {
            linkedAccounts = LinkedAccounts(accounts: try OTPAuthParser.parse(url.absoluteString))
        } catch {
            linkError = error.localizedDescription
        }
    }

    /// Adds the confirmed accounts, skipping any that already exist.
    func addLinkedAccounts(_ accounts: [OTPAccount]) {
        Task {
            if !twoFactorModel.hasLoaded { await twoFactorModel.refresh() }
            do {
                try await twoFactorModel.add(accounts)
            } catch {
                linkError = error.muninDescription
            }
        }
    }
}

/// Accounts from a 2FA setup link, presented as a dialog item.
private struct LinkedAccounts: Identifiable {
    /// A unique identifier, so each link presents a new dialog.
    let id = UUID()
    /// The accounts in the link.
    let accounts: [OTPAccount]
}
