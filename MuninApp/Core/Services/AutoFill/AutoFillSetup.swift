import AuthenticationServices
import Foundation
import Observation

/// An object that tracks and enables the app as an AutoFill provider.
///
/// The status is checked when the app becomes active, so it reflects changes
/// made in Settings. While AutoFill is off, the vault shows a banner leading to
/// the setup guide until the user dismisses it.
@Observable
final class AutoFillSetup {
    /// The user defaults key for ``isBannerDismissed``.
    private static let bannerDismissedKey = "munin.autofill.bannerDismissed"

    /// A Boolean value that indicates whether the app is enabled as an AutoFill provider; `nil` until checked.
    private(set) var isEnabled: Bool?

    /// A Boolean value that indicates whether the user dismissed the AutoFill banner.
    ///
    /// Persisted across launches. The guide remains available in Settings.
    var isBannerDismissed = UserDefaults.standard.bool(forKey: AutoFillSetup.bannerDismissedKey) {
        didSet { UserDefaults.standard.set(isBannerDismissed, forKey: Self.bannerDismissedKey) }
    }
    /// A Boolean value that indicates whether the setup guide is presented.
    var isGuidePresented = false

    /// Creates an AutoFill setup state that hasn't been checked yet.
    init() {}
}

// MARK: - Actions
extension AutoFillSetup {
    /// A Boolean value that indicates whether the vault shows the AutoFill
    /// banner: AutoFill is off and the banner hasn't been dismissed.
    var showsBanner: Bool {
        isEnabled == false && !isBannerDismissed
    }

    /// Updates ``isEnabled`` from the system's AutoFill status.
    func refresh() async {
        isEnabled = await ASCredentialIdentityStore.shared.state().isEnabled
    }

    /// Shows the system prompt to enable the app as an AutoFill provider, and dismisses the guide if that succeeds.
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
