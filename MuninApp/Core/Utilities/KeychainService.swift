import Foundation
import Security

enum KeychainService {
    private static let service = Bundle.main.bundleIdentifier ?? "dev.gidlof.Munin"
    private static let supabaseAccount = "supabase.token"
    private static let supabaseRefreshAccount = "supabase.refresh_token"
    private static let userIDAccount = "supabase.user_id"
    private static let emailAccount = "supabase.email"

    // MARK: - Supabase session

    static func saveSupabaseToken(_ token: String) { save(token, account: supabaseAccount) }
    static func loadSupabaseToken() -> String? { load(account: supabaseAccount) }
    static func deleteSupabaseToken() { delete(account: supabaseAccount) }

    static func saveSupabaseRefreshToken(_ token: String) { save(token, account: supabaseRefreshAccount) }
    static func loadSupabaseRefreshToken() -> String? { load(account: supabaseRefreshAccount) }
    static func deleteSupabaseRefreshToken() { delete(account: supabaseRefreshAccount) }

    // MARK: - Signed-in user

    static func saveUserID(_ id: String) { save(id, account: userIDAccount) }
    static func loadUserID() -> String? { load(account: userIDAccount) }
    static func deleteUserID() { delete(account: userIDAccount) }

    static func saveEmail(_ email: String) { save(email, account: emailAccount) }
    static func loadEmail() -> String? { load(account: emailAccount) }
    static func deleteEmail() { delete(account: emailAccount) }

    // MARK: - iCloud Keychain (synced to the user's other Apple devices)

    static func loadSynced(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func saveSynced(_ data: Data, account: String) {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = true
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        // Synced items can't be ThisDeviceOnly.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Private

    private static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String, account: String) {
        delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // macOS: use the iOS-style keychain, so there's no login-keychain prompt.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
