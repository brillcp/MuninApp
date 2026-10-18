import SwiftUI

/// Sidebar on Mac and iPad, tab bar on iPhone.
struct MainView: View {
    let vault: UnlockedVault

    enum Section: Hashable {
        case vault
        case codes
    }

    @State private var selection: Section = .vault

    var body: some View {
        TabView(selection: $selection) {
            Tab("main.tab.vault", systemImage: "lock.rectangle.stack", value: Section.vault) {
                VaultView(vault: vault)
            }
            Tab("main.tab.codes", systemImage: "key.viewfinder", value: Section.codes) {
                CodesView(vault: vault)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(macOS)
        .tabViewSidebarBottomBar {
            AccountMenu()
                .menuStyle(.button)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        #endif
    }
}

#Preview {
    MainView(vault: .preview)
        .environment(AuthManager())
        .environment(VaultSession())
}
