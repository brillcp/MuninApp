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

    private var root: some View {
        ContentView()
            .environment(auth)
            .environment(session)
    }
}
