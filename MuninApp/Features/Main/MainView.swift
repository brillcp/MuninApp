import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The root view of the unlocked app, with a sidebar on macOS and iPad and a
/// tab bar on iPhone.
///
/// The main section holds the vault and 2FA tabs. On iOS, Settings and Search
/// are tabs too; on macOS, Settings is a separate window linked from the
/// sidebar's bottom bar. The Search tab uses the `.search` role, so the system
/// places it at the trailing edge of the tab bar, and it opens passwords in
/// its own navigation stack.
struct MainView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    /// The vault model shared by the vault, Search, and the macOS menu bar.
    @Environment(VaultViewModel.self) private var vaultModel
    /// The subscription state, used to show the paywall while the vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// The AutoFill setup state, used to present the setup guide.
    @Environment(AutoFillSetup.self) private var autoFill

    @State private var selection: Section = .vault
    /// The 2FA model shared by the 2FA and Search tabs.
    @State private var twoFactorModel: TwoFactorViewModel
    /// Accounts from a 2FA setup link, awaiting confirmation.
    @State private var linkedAccounts: LinkedAccounts?
    /// The reason a 2FA setup link couldn't be added, shown in an alert.
    @State private var linkError: String?

    /// A 2FA setup link that opened the app, cleared once handled.
    @Binding var pendingCodeLink: URL?

    /// Creates the main view.
    ///
    /// - Parameters:
    ///   - session: The vault session used to create the 2FA model.
    ///   - pendingCodeLink: A binding to a 2FA setup link waiting to be handled.
    init(session: VaultSession, pendingCodeLink: Binding<URL?>) {
        _twoFactorModel = State(initialValue: TwoFactorViewModel(session: session))
        _pendingCodeLink = pendingCodeLink
    }

    var body: some View {
        @Bindable var subscriptions = subscriptions
        @Bindable var vaultModel = vaultModel
        @Bindable var autoFill = autoFill
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
            }
            #if os(iOS)
            Tab("settings.title", systemImage: DesignKit.Icon.settings, value: Section.settings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("settings.title")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab(value: Section.search, role: .search) {
                SearchView(vaultModel: vaultModel, twoFactorModel: twoFactorModel)
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        .scrollIndicators(.never)
        .task { await subscriptions.start(auth: auth) }
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
        .onChange(of: pendingCodeLink, initial: true, openPendingCodeLink)
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
        #endif
        #if os(macOS)
        .tabViewSidebarBottomBar {
            SettingsLink {
                Label {
                    if let email = auth.email {
                        Text(verbatim: email)
                    } else {
                        Text("settings.title")
                    }
                } icon: {
                    Image(systemName: DesignKit.Icon.settingsSelected)
                }
            }
            .buttonStyle(.glassProminent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical)
        }
        #endif
    }
}

extension MainView {
    /// The app's top-level tabs.
    enum Section: Hashable {
        case vault
        case twoFactor
        case search
        case settings
    }
}

private extension MainView {
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
            if !twoFactorModel.hasLoaded { await twoFactorModel.refresh(auth: auth) }
            do {
                try await twoFactorModel.add(accounts, auth: auth)
            } catch {
                linkError = error.muninDescription
            }
        }
    }
}

/// Accounts from a 2FA setup link, presented as a dialog item.
private struct LinkedAccounts: Identifiable {
    let id = UUID()
    let accounts: [OTPAccount]
}
