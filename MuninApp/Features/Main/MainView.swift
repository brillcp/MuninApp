import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The unlocked app: a sidebar on Mac and iPad, a tab bar on iPhone.
///
/// The Munin section holds Vault and 2FA. On iOS there are also a Settings tab
/// (the Mac has a Settings window, ⌘, instead) and a Search tab. Search comes
/// last with the `.search` role, so iOS 26 shows it as its own button at the
/// trailing edge of the tab bar, and selecting it opens the search field.
/// Search opens passwords in its own navigation stack. On the Mac the
/// sidebar's bottom bar links to Settings.
struct MainView: View {
    /// The tabs.
    enum Section: Hashable {
        case vault
        case twoFactor
        case search
        case settings
    }

    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    /// The selected tab.
    @State private var selection: Section = .vault
    /// From the app (also used by the Mac menu bar), shared by Vault and Search.
    @Environment(VaultViewModel.self) private var vaultModel
    /// Shows the paywall after unlocking while the vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// Presents the AutoFill setup guide from the Vault's banner.
    @Environment(AutoFillSetup.self) private var autoFill
    /// Shared by the 2FA and Search tabs.
    @State private var twoFactorModel: TwoFactorViewModel
    /// Accounts from a 2FA setup link, waiting for confirmation.
    @State private var linkedAccounts: LinkedAccounts?
    /// Why a 2FA setup link couldn't be added, shown in an alert.
    @State private var linkError: String?

    /// A 2FA setup link that opened Munin; cleared once it's handled.
    @Binding var pendingCodeLink: URL?

    /// Creates the 2FA view model for `session`.
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

private extension MainView {
    /// Opens a 2FA setup link: switches to 2FA and asks to add its accounts.
    /// Read-only without a subscription, so then it says why instead.
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

    /// Adds the confirmed accounts, skipping ones already in Munin.
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
    /// The link's accounts.
    let accounts: [OTPAccount]
}

/// A tab's label. The Mac sidebar tints SF Symbols with the system accent,
/// ignoring .tint, .listItemTint and .foregroundStyle, so there the symbol is
/// rendered into a non-template image in fixed colours (the accent, or white
/// on the selected row), which the sidebar can't recolour.
private struct SidebarTabLabel: View {
    /// The tab's name.
    let title: LocalizedStringKey
    /// The tab's SF Symbol.
    let systemImage: String
    /// Whether the tab is selected, so the Mac icon turns white.
    let isSelected: Bool

    var body: some View {
        Label {
            Text(title)
        } icon: {
            #if os(macOS)
            if let image = coloredSymbol {
                Image(nsImage: image)
            } else {
                Image(systemName: systemImage)
            }
            #else
            Image(systemName: systemImage)
            #endif
        }
    }

    #if os(macOS)
    /// The symbol rendered as a non-template image in the accent colour, or
    /// white when selected. Nil if the symbol doesn't exist.
    private var coloredSymbol: NSImage? {
        let color = isSelected ? NSColor.white : NSColor(resource: .accent)
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }
    #endif
}
