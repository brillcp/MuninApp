import Foundation

/// The server addresses and public keys the app uses.
enum APIConfig {
    /// The base URL of the Munin API.
    static let apiBaseURL = URL(string: "https://munin-baemyjv7oq-ew.a.run.app/v1")!
    /// The URL of the authentication project.
    static let authProjectURL = "https://sdmkixehvwtqxmcudrxv.supabase.co"
    /// The base URL for authentication, used to exchange Apple identity tokens
    /// and refresh sessions.
    static let authBaseURL = URL(string: "\(authProjectURL)/auth/v1")!
    /// The authentication project's publishable key.
    ///
    /// This key is public by design: it identifies the project and grants no
    /// access by itself.
    static let anonKey = "sb_publishable_8ooB5sdO_KYMjg5vBndxcA__jILZOW9"

    /// A Boolean value that indicates whether ``anonKey`` holds a real key
    /// rather than a placeholder.
    static var isAnonKeyConfigured: Bool { !anonKey.hasPrefix("PASTE_") }
}
