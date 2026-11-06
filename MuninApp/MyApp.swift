import SwiftUI

/// The app's entry point.
///
/// On macOS, the app provides a main window, a Settings window, and a menu bar
/// extra. On iOS, it provides a single window group. All scenes share one
/// ``AuthManager``, ``VaultSession``, ``VaultViewModel``, and
/// ``SubscriptionManager``.
@main struct MyApp: App {
    @State private var auth = AuthManager()
    @State private var session: VaultSession
    /// The password list, shared by the main window and the Mac menu bar.
    @State private var vaultModel: VaultViewModel
    /// The App Store subscription, shared by the main window and Settings.
    @State private var subscriptions = SubscriptionManager()
    /// The AutoFill extension's status, shared by the main window and Settings.
    @State private var autoFill = AutoFillSetup()

    /// Creates the shared models and, on macOS, applies the AppKit color
    /// overrides for table selection and accent.
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
            root.frame(minWidth: 900, minHeight: 600)
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
                .environment(autoFill)
                .tint(.accent)
        }

        MenuBarExtra("main.window.title", image: DesignKit.Asset.menuBarIcon) {
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

    /// The identifier of the main window on macOS, used by the menu bar's Open button.
    static let mainWindowID = "main"

    /// The root view with the shared models in its environment.
    ///
    /// The app's tint is set once here; views override it only where they
    /// need a different color, such as the countdown gauge.
    private var root: some View {
        ContentView()
            .environment(auth)
            .environment(session)
            .environment(vaultModel)
            .environment(subscriptions)
            .environment(autoFill)
            .tint(.accent)
    }
}
