import Foundation

/// The server addresses and public keys the app uses.
///
/// The values come from the build settings in `Config/Base.xcconfig` and reach
/// the app through the `Info.plist` keys `MuninAPIHost`, `SupabaseHost`, and `SupabasePublishableKey`.
enum APIConfig {
    /// The base URL of the Munin API.
    static let apiBaseURL = URL(string: "https://\(infoValue("MuninAPIHost"))/v1")!
    /// The URL of the authentication project.
    static let authProjectURL = "https://\(infoValue("SupabaseHost"))"
    /// The base URL for authentication, used to exchange Apple identity tokens
    /// and refresh sessions.
    static let authBaseURL = URL(string: "\(authProjectURL)/auth/v1")!
    /// The authentication project's publishable key.
    ///
    /// This key is public by design: it identifies the project and grants no
    /// access by itself.
    static let anonKey = infoValue("SupabasePublishableKey")

    /// A Boolean value that indicates whether ``anonKey`` holds a real key
    /// rather than an empty value or a placeholder.
    static var isAnonKeyConfigured: Bool { !anonKey.isEmpty && !anonKey.hasPrefix("PASTE_") }
}

private extension APIConfig {
    /// Returns the string for an `Info.plist` key, or an empty string if the key is missing.
    static func infoValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
