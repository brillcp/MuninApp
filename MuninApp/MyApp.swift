import SwiftUI

/// The app's entry point.
///
/// On macOS, the app provides a main window, a Settings window, and a menu bar
/// extra. On iOS, it provides a single window group.
///
/// This is the composition root: it creates the API client and every shared
/// model once, passes each its dependencies, and puts the models in the
/// environment of all scenes.
@main struct MyApp: App {
    @State private var auth: AuthManager
    @State private var session: VaultSession
    /// The password list, shared by the main window and the Mac menu bar.
    @State private var vaultModel: VaultViewModel
    /// The 2FA accounts, shared by the 2FA tab, Search, and imports.
    @State private var twoFactorModel: TwoFactorViewModel
    /// The stored cards, shared by the Cards tab and Search.
    @State private var cardsModel: CardsViewModel
    /// The App Store subscription, shared by the main window and Settings.
    @State private var subscriptions: SubscriptionManager
    /// The model behind Settings.
    @State private var settingsModel: SettingsViewModel
    /// The AutoFill extension's status, shared by the main window and Settings.
    @State private var autoFill = AutoFillSetup()
    /// The App Store update check, run once at launch.
    @State private var updateChecker = AppUpdateChecker()

    /// Creates the shared models and, on macOS, applies the AppKit color
    /// overrides for table selection and accent.
    init() {
        let api = MuninService(tokenProvider: .shared)
        let auth = AuthManager(tokenProvider: .shared, api: api)
        let session = VaultSession(api: api, user: auth)
        let subscriptions = SubscriptionManager(api: api, user: auth)
        _auth = State(initialValue: auth)
        _session = State(initialValue: session)
        _vaultModel = State(initialValue: VaultViewModel(session: session, api: api, user: auth))
        _twoFactorModel = State(initialValue: TwoFactorViewModel(session: session, api: api, user: auth))
        _cardsModel = State(initialValue: CardsViewModel(session: session, api: api, user: auth))
        _subscriptions = State(initialValue: subscriptions)
        _settingsModel = State(initialValue: SettingsViewModel(api: api, auth: auth, session: session, subscriptions: subscriptions))
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
                .environment(settingsModel)
                .environment(autoFill)
                .tint(.accent)
                .scrollEdgeEffectStyle(.soft, for: .top)
        }

        MenuBarExtra("main.window.title", image: DesignKit.Asset.menuBarIcon) {
            MenuBarContent()
                .environment(auth)
                .environment(session)
                .environment(vaultModel)
                .tint(.accent)
                .scrollEdgeEffectStyle(.soft, for: .top)
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
    /// The app's tint and the soft top scroll edge are set once here; views
    /// override the tint only where they need a different color, such as the
    /// countdown gauge.
    private var root: some View {
        ContentView()
            .environment(auth)
            .environment(session)
            .environment(vaultModel)
            .environment(twoFactorModel)
            .environment(cardsModel)
            .environment(subscriptions)
            .environment(settingsModel)
            .environment(autoFill)
            .environment(updateChecker)
            .tint(.accent)
            .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
