import AuthenticationServices
import Foundation
import Observation

/// An object that tracks and enables the app as an AutoFill provider.
///
/// The status is checked when the app becomes active, so it reflects changes
/// made in Settings. While AutoFill is off, the setup guide opens by itself
/// once, and the vault shows a banner leading to it until the user dismisses it.
@Observable
final class AutoFillSetup {
    /// The user defaults key for ``isBannerDismissed``.
    private static let bannerDismissedKey = "munin.autofill.bannerDismissed"
    /// The user defaults key that records that the guide opened by itself.
    private static let guideShownKey = "munin.autofill.guideShown"

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

    /// Opens the setup guide if AutoFill is off and the guide hasn't opened by itself before.
    ///
    /// It opens at most once per device; afterwards the banner and Settings lead to it.
    func presentGuideIfNeeded() {
        guard isEnabled == false, !UserDefaults.standard.bool(forKey: Self.guideShownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.guideShownKey)
        isGuidePresented = true
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
