import Foundation
import LocalAuthentication
import Security

/// A namespace for reading and writing the app's keychain items.
///
/// All items live in the data protection keychain under a single service. Most
/// are stored in an access group shared with the AutoFill extension, so both
/// see the same session and the same biometric copy of the vault key.
///
/// - Session tokens and user details are stored on this device only.
/// - Synced items, such as the legacy vault key, sync through iCloud Keychain
///   and live outside the shared group.
/// - Biometric items require Face ID or Touch ID to read.
///
/// Items found outside the shared group are moved into it when first read.
nonisolated enum KeychainService {
    /// The keychain service for all items.
    ///
    /// This is the app's bundle identifier, used by the extension as well.
    private static let service = "dev.gidlof.Munin"
    /// The keychain access group shared by the app and the AutoFill extension.
    ///
    /// Read from the `MuninKeychainGroup` Info.plist key, which includes the team prefix.
    private static let sharedGroup = Bundle.main.object(forInfoDictionaryKey: "MuninKeychainGroup") as? String
    private static let accessTokenAccount = "auth.token"
    private static let refreshTokenAccount = "auth.refresh_token"
    private static let userIDAccount = "auth.user_id"
    private static let emailAccount = "auth.email"

    // MARK: - Session

    /// Saves the access token.
    static func saveAccessToken(_ token: String) { save(token, account: accessTokenAccount) }
    /// Returns the saved access token.
    static func loadAccessToken() -> String? { load(account: accessTokenAccount) }
    /// Deletes the access token.
    static func deleteAccessToken() { delete(account: accessTokenAccount) }

    /// Saves the refresh token.
    static func saveRefreshToken(_ token: String) { save(token, account: refreshTokenAccount) }
    /// Returns the saved refresh token.
    static func loadRefreshToken() -> String? { load(account: refreshTokenAccount) }
    /// Deletes the refresh token.
    static func deleteRefreshToken() { delete(account: refreshTokenAccount) }

    // MARK: - Signed-in user

    /// Saves the signed-in user's identifier.
    static func saveUserID(_ id: String) { save(id, account: userIDAccount) }
    /// Returns the saved user identifier.
    static func loadUserID() -> String? { load(account: userIDAccount) }
    /// Deletes the saved user identifier.
    static func deleteUserID() { delete(account: userIDAccount) }

    /// Saves the signed-in user's email address.
    static func saveEmail(_ email: String) { save(email, account: emailAccount) }
    /// Returns the saved email address.
    static func loadEmail() -> String? { load(account: emailAccount) }
    /// Deletes the saved email address.
    static func deleteEmail() { delete(account: emailAccount) }

    // MARK: - iCloud Keychain

    /// Returns the data of an item synced through iCloud Keychain.
    static func loadSynced(account: String) -> Data? {
        var query = baseQuery(account: account, inSharedGroup: false)
        query[kSecAttrSynchronizable as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Saves an item that syncs to the user's other devices through iCloud Keychain.
    ///
    /// Replaces any existing item for the account.
    static func saveSynced(_ data: Data, account: String) {
        var query = baseQuery(account: account, inSharedGroup: false)
        query[kSecAttrSynchronizable as String] = true
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        // Synced items can't be ThisDeviceOnly.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Deletes a synced item from all of the user's devices.
    static func deleteSynced(account: String) {
        var query = baseQuery(account: account, inSharedGroup: false)
        query[kSecAttrSynchronizable as String] = true
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Biometrics

    /// The result of reading a biometric item.
    enum BiometricRead {
        /// The user authenticated, and the item's data was read.
        case success(Data)
        /// No item was found.
        case notFound
        /// The user dismissed the prompt.
        case canceled
        /// Authentication failed, or the keychain returned another error.
        case failed
    }

    /// Saves an item that requires Face ID or Touch ID to read.
    ///
    /// The item stays on this device and becomes unreadable if the enrolled
    /// biometrics change.
    ///
    /// - Returns: `true` if the item was saved.
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

    /// Reads a biometric item, prompting the user to authenticate.
    ///
    /// This call blocks until the user responds, so don't call it on the main thread.
    ///
    /// - Parameters:
    ///   - account: The item's account name.
    ///   - reason: The explanation shown in the authentication prompt.
    static func loadBiometric(account: String, reason: String) -> BiometricRead {
        let context = LAContext()
        context.localizedReason = reason
        // The lock screen has its own "Use Master Password" button.
        context.localizedFallbackTitle = ""

        var query = baseQuery(account: account, inSharedGroup: false)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else { return .failed }
            if !hasBiometric(account: account, inSharedGroup: true) {
                // Move the item into the shared group so the AutoFill extension can read it.
                _ = saveBiometric(data, account: account)
            }
            return .success(data)
        case errSecItemNotFound:
            return .notFound
        case errSecUserCanceled:
            return .canceled
        default:
            return .failed
        }
    }

    /// Returns a Boolean value that indicates whether a biometric item exists, without prompting.
    ///
    /// - Parameters:
    ///   - account: The item's account name.
    ///   - inSharedGroup: Whether to search only the shared access group, rather
    ///     than every group the app can reach.
    static func hasBiometric(account: String, inSharedGroup: Bool = false) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery(account: account, inSharedGroup: inSharedGroup)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Deletes a biometric item without prompting.
    static func deleteBiometric(account: String) {
        deleteEverywhere(account: account)
    }

    // MARK: - Private

    /// Returns an item's value as a UTF-8 string.
    ///
    /// An item found outside the shared group is moved into it.
    private static func load(account: String) -> String? {
        if let data = read(baseQuery(account: account)) {
            return String(data: data, encoding: .utf8)
        }
        guard sharedGroup != nil,
              let data = read(baseQuery(account: account, inSharedGroup: false)),
              let value = String(data: data, encoding: .utf8) else { return nil }
        save(value, account: account)
        return value
    }

    /// Returns the data of the first item matching the query, without prompting.
    private static func read(_ query: [String: Any]) -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Saves a string to the shared group on this device only, replacing any existing item.
    private static func save(_ value: String, account: String) {
        deleteEverywhere(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete(account: String) {
        deleteEverywhere(account: account)
    }

    /// Deletes the item from every access group the app can reach.
    private static func deleteEverywhere(account: String) {
        SecItemDelete(baseQuery(account: account, inSharedGroup: false) as CFDictionary)
    }

    /// Returns the base query for an item: its class, service, and account.
    ///
    /// - Parameter inSharedGroup: Whether to scope the query to the shared
    ///   access group. When `false`, a search covers every group the app can reach.
    private static func baseQuery(account: String, inSharedGroup: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // On macOS, use the data protection keychain to avoid login keychain prompts.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if inSharedGroup, let sharedGroup {
            query[kSecAttrAccessGroup as String] = sharedGroup
        }
        return query
    }
}
