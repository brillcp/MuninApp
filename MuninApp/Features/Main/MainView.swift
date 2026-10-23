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
/// Opening a password from Search selects it in the Vault tab, which handles
/// editing and deleting. On the Mac the sidebar's bottom bar links to Settings.
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
    /// Shared by the 2FA and Search tabs.
    @State private var twoFactorModel: TwoFactorViewModel

    /// Creates the 2FA view model for `session`.
    init(session: VaultSession) {
        _twoFactorModel = State(initialValue: TwoFactorViewModel(session: session))
    }

    var body: some View {
        TabView(selection: $selection) {
            TabSection("main.section.munin") {
                Tab(value: Section.vault) {
                    VaultView(viewModel: vaultModel)
                } label: {
                    SidebarTabLabel(title: "main.tab.vault", systemImage: "lock.rectangle.stack", isSelected: selection == .vault)
                }
                Tab(value: Section.twoFactor) {
                    TwoFactorView(viewModel: twoFactorModel)
                } label: {
                    SidebarTabLabel(title: "main.tab.codes", systemImage: "key.viewfinder", isSelected: selection == .twoFactor)
                }
            }
            #if os(iOS)
            Tab("settings.title", systemImage: "gearshape", value: Section.settings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("settings.title")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab(value: Section.search, role: .search) {
                SearchView(vaultModel: vaultModel, twoFactorModel: twoFactorModel) { item in
                    vaultModel.selection = item.id
                    selection = .vault
                }
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
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
                    Image(systemName: "gearshape.fill")
                }
            }
            .buttonStyle(.glassProminent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical)
        }
        #endif
    }
}

#Preview {
    MainView(session: VaultSession())
        .environment(VaultViewModel(session: VaultSession()))
        .environment(AuthManager())
        .environment(VaultSession())
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
