import SwiftUI

@main struct MyApp: App {
    @State private var auth = AuthManager()
    @State private var session: VaultSession
    /// The password list, shared by the main window and the Mac menu bar.
    @State private var vaultModel: VaultViewModel

    init() {
        let session = VaultSession()
        _session = State(initialValue: session)
        _vaultModel = State(initialValue: VaultViewModel(session: session))
        #if os(macOS)
        TableSelectionStyle.apply(color: NSColor(resource: .wood))
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // A single window: no "New Window", and the menu bar item reopens this one.
        Window("main.window.title", id: Self.mainWindowID) {
            root
                // Room for the sidebar, the password list and the detail
                // (each column needs at least 320).
                .frame(minWidth: 860, minHeight: 500)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            LockCommands(session: session)
            FindCommands()
        }

        Settings {
            SettingsView()
                .environment(auth)
                .environment(session)
                .tint(.accent)
        }

        MenuBarExtra("main.window.title", systemImage: "key.viewfinder") {
            MenuBarContent()
                .environment(auth)
                .environment(session)
                .environment(vaultModel)
                .tint(.accent)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            root
        }
        .commands {
            LockCommands(session: session)
            FindCommands()
        }
        #endif
    }

    static let mainWindowID = "main"

    /// The app's tint is set once here; views only override it where they
    /// need something else (e.g. the countdown gauge).
    private var root: some View {
        ContentView()
            .environment(auth)
            .environment(session)
            .environment(vaultModel)
            .tint(.accent)
    }
}
