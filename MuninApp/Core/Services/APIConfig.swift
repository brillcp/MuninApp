import Foundation

/// Server addresses and public keys the app talks to.
enum APIConfig {
    /// Munin's API, on Cloud Run.
    static let apiBaseURL = URL(string: "https://munin-877897891391.us-central1.run.app/v1")!
    /// Munin's own Supabase project.
    static let supabaseURL = "https://sdmkixehvwtqxmcudrxv.supabase.co"
    /// Base URL for Supabase Auth: the Apple identity token exchange and token refresh.
    static let authBaseURL = URL(string: "\(supabaseURL)/auth/v1")!
    /// Supabase's publishable key. Public by design: it identifies the project
    /// and grants nothing by itself.
    static let anonKey = "sb_publishable_8ooB5sdO_KYMjg5vBndxcA__jILZOW9"

    /// False while `anonKey` still holds the placeholder.
    static var isAnonKeyConfigured: Bool { !anonKey.hasPrefix("PASTE_") }
}
