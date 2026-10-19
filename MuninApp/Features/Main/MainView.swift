import SwiftUI

/// Sidebar on Mac and iPad, tab bar on iPhone.
struct MainView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session

    enum Section: Hashable {
        case vault
        case codes
    }

    @State private var selection: Section = .vault

    var body: some View {
        TabView(selection: $selection) {
            TabSection("main.section.munin") {
                Tab("main.tab.vault", systemImage: "lock.rectangle.stack", value: Section.vault) {
                    VaultView(session: session)
                }
                Tab("main.tab.codes", systemImage: "key.viewfinder", value: Section.codes) {
                    CodesView(session: session)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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
            .padding()
        }
        #endif
    }
}

#Preview {
    MainView()
        .environment(AuthManager())
        .environment(VaultSession())
}
