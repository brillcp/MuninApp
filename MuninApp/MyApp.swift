import SwiftUI

@main struct MyApp: App {
    @State private var auth = AuthManager()
    @State private var session = VaultSession()

    init() {
        #if os(macOS)
        TableSelectionStyle.apply(color: NSColor(resource: .wood))
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // A single window: no "New Window", and the menu bar item reopens this one.
        Window("main.window.title", id: Self.mainWindowID) {
            root
        }
        .defaultSize(width: 900, height: 600)
        .commands { LockCommands(session: session) }

        Settings {
            SettingsView()
                .environment(auth)
                .environment(session)
                .tint(.accent)
        }

        MenuBarExtra("main.window.title", systemImage: "key.viewfinder") {
            MenuBarContent(session: session)
        }
        #else
        WindowGroup {
            root
        }
        .commands { LockCommands(session: session) }
        #endif
    }

    static let mainWindowID = "main"

    /// The app's tint is set once here; views only override it where they
    /// need something else (e.g. the countdown gauge).
    private var root: some View {
        ContentView()
            .environment(auth)
            .environment(session)
            .tint(.accent)
    }
}
