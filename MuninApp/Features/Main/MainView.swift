import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Sidebar on Mac and iPad, tab bar on iPhone.
struct MainView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session

    enum Section: Hashable {
        case vault
        case codes
        case search
        case settings
    }

    @State private var selection: Section = .vault
    /// From the app (also used by the Mac menu bar), shared by Vault and Search.
    @Environment(VaultViewModel.self) private var vaultModel
    /// Shared by the 2FA and Search tabs.
    @State private var codesModel: CodesViewModel

    init(session: VaultSession) {
        _codesModel = State(initialValue: CodesViewModel(session: session))
    }

    var body: some View {
        TabView(selection: $selection) {
            TabSection("main.section.munin") {
                Tab(value: Section.vault) {
                    VaultView(viewModel: vaultModel)
                } label: {
                    SidebarTabLabel(title: "main.tab.vault", systemImage: "lock.rectangle.stack", isSelected: selection == .vault)
                }
                Tab(value: Section.codes) {
                    CodesView(viewModel: codesModel)
                } label: {
                    SidebarTabLabel(title: "main.tab.codes", systemImage: "key.viewfinder", isSelected: selection == .codes)
                }
            }
            #if os(iOS)
            // The Mac has a Settings window (⌘,) instead.
            Tab("settings.title", systemImage: "gearshape", value: Section.settings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("settings.title")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            // Last, so iOS 26 shows it as its own bubble next to the tab bar.
            Tab(value: Section.search, role: .search) {
                SearchView(vaultModel: vaultModel, codesModel: codesModel) { item in
                    // Open the password in the Vault tab, which handles edit and delete.
                    vaultModel.selection = item.id
                    selection = .vault
                }
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        // As in PokedexUI: the .search tab becomes its own button at the trailing
        // edge, and selecting it opens the search field.
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
                    Image(systemName: "person.crop.circle")
                }
            }
            .buttonStyle(.borderless)
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
    let title: LocalizedStringKey
    let systemImage: String
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
