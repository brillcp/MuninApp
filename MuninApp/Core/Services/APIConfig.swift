import Foundation

/// Server addresses and public keys the app talks to.
enum APIConfig {
    /// Munin's API. TODO: switch to the Cloud Run URL once Munin is deployed.
    ///
    /// A physical iPhone can't reach the Mac's `localhost`, so device builds use
    /// the Mac's Bonjour name (`scutil --get LocalHostName` + ".local").
    #if os(iOS) && !targetEnvironment(simulator)
    static let apiBaseURL = URL(string: "http://VGs-MBP-M4.local:8080/v1")!
    #else
    static let apiBaseURL = URL(string: "http://localhost:8080/v1")!
    #endif
    /// Munin's own Supabase project.
    static let supabaseURL = "https://sdmkixehvwtqxmcudrxv.supabase.co"
    /// Base URL for Supabase Auth: the Apple identity token exchange and token refresh.
    static let authBaseURL = URL(string: "\(supabaseURL)/auth/v1")!
    /// Public publishable (anon) key, safe to embed in the client.
    ///
    /// Supabase dashboard ▸ Project Settings ▸ API Keys.
    static let anonKey = "sb_publishable_8ooB5sdO_KYMjg5vBndxcA__jILZOW9"

    /// False while `anonKey` still holds the placeholder.
    static var isAnonKeyConfigured: Bool { !anonKey.hasPrefix("PASTE_") }
}
