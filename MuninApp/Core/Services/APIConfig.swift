import Foundation

/// Server addresses and public keys the app talks to.
enum APIConfig {
    /// Munin's API, on Cloud Run.
    static let apiBaseURL = URL(string: "https://munin-baemyjv7oq-ew.a.run.app/v1")!
    /// Munin's auth project.
    static let authProjectURL = "https://sdmkixehvwtqxmcudrxv.supabase.co"
    /// Base URL for auth: the Apple identity token exchange and token refresh.
    static let authBaseURL = URL(string: "\(authProjectURL)/auth/v1")!
    /// The auth project's publishable key. Public by design: it identifies the project
    /// and grants nothing by itself.
    static let anonKey = "sb_publishable_8ooB5sdO_KYMjg5vBndxcA__jILZOW9"

    /// False while `anonKey` still holds the placeholder.
    static var isAnonKeyConfigured: Bool { !anonKey.hasPrefix("PASTE_") }
}
