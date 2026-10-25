import Foundation

/// Web pages the app links to: shown on the paywall and in Settings.
enum AppLinks {
    /// Munin's privacy policy.
    static let privacyPolicy = URL(string: "https://gidlof.dev/munin-policy")!
    /// The App Store's subscription management page (Mac; iOS uses the system sheet).
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
    /// Terms of use: Apple's standard licensed application end user licence agreement.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
