import SwiftUI

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
                Tab("main.tab.vault", systemImage: "lock.rectangle.stack", value: Section.vault) {
                    VaultView(viewModel: vaultModel)
                }
                Tab("main.tab.codes", systemImage: "key.viewfinder", value: Section.codes) {
                    CodesView(viewModel: codesModel)
                }
            }
            #if os(iOS)
            // The Mac has a Settings window (⌘,) instead.
            Tab("settings.title", systemImage: "gearshape", value: Section.settings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("settings.title")
                        .barkNavigationBar()
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
