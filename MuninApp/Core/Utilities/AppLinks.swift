import Foundation

/// Web pages the app links to from the paywall and Settings.
enum AppLinks {
    /// The app's privacy policy.
    static let privacyPolicy = URL(string: "https://gidlof.dev/munin-policy")!
    /// The App Store subscription management page, used on macOS; iOS uses the system sheet.
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
    /// The terms of use: Apple's standard licensed application end user license agreement.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
