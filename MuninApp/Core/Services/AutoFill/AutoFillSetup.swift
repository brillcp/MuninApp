import AuthenticationServices
import Foundation
import Observation

/// Whether Munin is turned on as an AutoFill provider, and turning it on.
///
/// Checked when the app becomes active, so it notices when the user comes
/// back from Settings. While it's off, the Vault shows a banner leading to
/// the setup guide, until the user dismisses it.
@Observable
final class AutoFillSetup {
    /// UserDefaults key for `isBannerDismissed`.
    private static let bannerDismissedKey = "munin.autofill.bannerDismissed"

    /// Whether Munin is turned on in AutoFill settings; nil until checked.
    private(set) var isEnabled: Bool?

    /// Set when the user closes the Vault's AutoFill banner. Remembered
    /// between launches; the guide stays reachable from Settings.
    var isBannerDismissed = UserDefaults.standard.bool(forKey: AutoFillSetup.bannerDismissedKey) {
        didSet { UserDefaults.standard.set(isBannerDismissed, forKey: Self.bannerDismissedKey) }
    }
    /// Shows the setup guide from the Vault's banner.
    var isGuidePresented = false

    /// Creates a setup state that hasn't been checked yet.
    init() {}
}

// MARK: - Public functions
extension AutoFillSetup {
    /// Whether the Vault shows the banner: AutoFill is off and the banner
    /// hasn't been dismissed.
    var showsBanner: Bool {
        isEnabled == false && !isBannerDismissed
    }

    /// Asks the system whether Munin is turned on.
    func refresh() async {
        isEnabled = await ASCredentialIdentityStore.shared.state().isEnabled
    }

    /// Shows the system's prompt to turn Munin on. Closes the guide if it was.
    func turnOn() async {
        if await ASSettingsHelper.requestToTurnOnCredentialProviderExtension() {
            isEnabled = true
            isGuidePresented = false
        } else {
            await refresh()
        }
    }

    /// Opens the AutoFill & Passwords page in Settings.
    func openSettings() async {
        try? await ASSettingsHelper.openCredentialProviderAppSettings()
    }
}
