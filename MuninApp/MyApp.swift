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
        AccentColorOverride.apply(color: NSColor(resource: .accent))
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        Window("main.window.title", id: Self.mainWindowID) {
            root
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 860)
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
