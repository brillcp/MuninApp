import Foundation
import LocalAuthentication
import Security

/// Reads and writes the app's Keychain items.
///
/// Everything lives in the data protection keychain under the app's bundle
/// identifier. Session tokens and the user are this-device-only; the legacy
/// vault key is synced through iCloud Keychain; the biometric copy of the
/// vault key needs Face ID / Touch ID to read.
nonisolated enum KeychainService {
    /// The Keychain service all items are stored under.
    private static let service = Bundle.main.bundleIdentifier ?? "dev.gidlof.Munin"
    /// Account for the access token.
    private static let accessTokenAccount = "auth.token"
    /// Account for the refresh token.
    private static let refreshTokenAccount = "auth.refresh_token"
    /// Account for the signed-in user's ID.
    private static let userIDAccount = "auth.user_id"
    /// Account for the signed-in user's email.
    private static let emailAccount = "auth.email"

    // MARK: - Session

    /// Saves the access token.
    static func saveAccessToken(_ token: String) { save(token, account: accessTokenAccount) }
    /// The saved access token.
    static func loadAccessToken() -> String? { load(account: accessTokenAccount) }
    /// Deletes the access token.
    static func deleteAccessToken() { delete(account: accessTokenAccount) }

    /// Saves the refresh token.
    static func saveRefreshToken(_ token: String) { save(token, account: refreshTokenAccount) }
    /// The saved refresh token.
    static func loadRefreshToken() -> String? { load(account: refreshTokenAccount) }
    /// Deletes the refresh token.
    static func deleteRefreshToken() { delete(account: refreshTokenAccount) }

    // MARK: - Signed-in user

    /// Saves the signed-in user's ID.
    static func saveUserID(_ id: String) { save(id, account: userIDAccount) }
    /// The saved user ID.
    static func loadUserID() -> String? { load(account: userIDAccount) }
    /// Deletes the saved user ID.
    static func deleteUserID() { delete(account: userIDAccount) }

    /// Saves the signed-in user's email.
    static func saveEmail(_ email: String) { save(email, account: emailAccount) }
    /// The saved email.
    static func loadEmail() -> String? { load(account: emailAccount) }
    /// Deletes the saved email.
    static func deleteEmail() { delete(account: emailAccount) }

    // MARK: - iCloud Keychain (synced to the user's other Apple devices)

    /// Reads a synced item.
    static func loadSynced(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Saves an item that syncs to the user's other devices through iCloud Keychain.
    static func saveSynced(_ data: Data, account: String) {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = true
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        // Synced items can't be ThisDeviceOnly.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Deletes a synced item, on every device.
    static func deleteSynced(account: String) {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = true
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Biometrics (this device only)

    /// The outcome of reading a biometric item.
    enum BiometricRead {
        /// The user authenticated; the item's data.
        case success(Data)
        /// No item was found.
        case notFound
        /// The user dismissed the prompt.
        case canceled
        /// Authentication failed, or another Keychain error.
        case failed
    }

    /// Saves an item that can only be read after Face ID / Touch ID, and stops
    /// working if the enrolled fingers or faces change. Never synced.
    static func saveBiometric(_ data: Data, account: String) -> Bool {
        deleteBiometric(account: account)
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else { return false }
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessControl as String] = access
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Shows the biometric prompt with `reason`. Blocks until the user responds.
    static func loadBiometric(account: String, reason: String) -> BiometricRead {
        let context = LAContext()
        context.localizedReason = reason
        // The lock screen has its own "Use Master Password" button.
        context.localizedFallbackTitle = ""

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else { return .failed }
            return .success(data)
        case errSecItemNotFound:
            return .notFound
        case errSecUserCanceled:
            return .canceled
        default:
            return .failed
        }
    }

    /// Deletes a biometric item. Doesn't prompt.
    static func deleteBiometric(account: String) {
        delete(account: account)
    }

    // MARK: - Private

    /// Reads a this-device item as a UTF-8 string.
    private static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves a string as a this-device item, replacing any existing one.
    private static func save(_ value: String, account: String) {
        delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Deletes the non-synced item for `account`.
    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    /// The query attributes every item shares: class, service and account.
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
