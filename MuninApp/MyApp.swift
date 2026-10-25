import SwiftUI

/// The app's entry point.
///
/// On the Mac: the main window, a Settings window and a menu bar window.
/// On iOS: a single window group. All of them share one `AuthManager`, one
/// `VaultSession`, one `VaultViewModel` and one `SubscriptionManager`.
@main struct MyApp: App {
    /// Sign-in state.
    @State private var auth = AuthManager()
    /// The vault key and lock state.
    @State private var session: VaultSession
    /// The password list, shared by the main window and the Mac menu bar.
    @State private var vaultModel: VaultViewModel
    /// The App Store subscription, shared by the main window and Settings.
    @State private var subscriptions = SubscriptionManager()

    /// Creates the shared models and, on the Mac, applies the AppKit colour
    /// overrides (table selection and accent).
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
            SectionCommands()
        }

        Settings {
            SettingsView()
                .environment(auth)
                .environment(session)
                .environment(subscriptions)
                .tint(.accent)
        }

        MenuBarExtra("main.window.title", systemImage: DesignKit.Icon.twoFactor) {
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

    /// The Mac main window's identifier, used by the menu bar's Open button.
    static let mainWindowID = "main"

    /// The root view with the shared models in its environment.
    ///
    /// The app's tint is set once here; views only override it where they
    /// need something else (for example the countdown gauge).
    private var root: some View {
        ContentView()
            .environment(auth)
            .environment(session)
            .environment(vaultModel)
            .environment(subscriptions)
            .tint(.accent)
    }
}
