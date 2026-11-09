import Foundation

/// The Munin API, as the app's models use it.
///
/// ``MuninService`` is the live implementation. Models receive an instance in
/// their initializer, so tests can pass a fake.
///
/// Calls that change or delete existing data take the master password
/// `proof` of the unlocked vault, which the server checks.
protocol MuninAPI: AnyObject, Sendable {
    // MARK: - 2FA accounts

    /// Fetches the user's encrypted 2FA accounts.
    func entries() async throws -> [EncryptedEntry]
    /// Stores an encrypted 2FA account.
    func createEntry(ciphertext: String) async throws -> EncryptedEntry
    /// Deletes a 2FA account.
    func deleteEntry(id: UUID, proof: String) async throws

    // MARK: - Passwords

    /// Fetches the user's encrypted password items.
    func passwords() async throws -> [EncryptedPassword]
    /// Stores a new password item.
    func createPassword(_ body: PasswordFieldsBody) async throws -> EncryptedPassword
    /// Replaces a password item's fields.
    func updatePassword(id: UUID, _ body: PasswordFieldsBody, proof: String) async throws -> EncryptedPassword
    /// Deletes a password item.
    func deletePassword(id: UUID, proof: String) async throws
    /// Updates a password item's modification date, such as after its password is copied.
    func touchPassword(id: UUID) async throws -> EncryptedPassword

    // MARK: - Vault key

    /// Fetches the wrapped vault key, or `nil` if no master password is set up.
    func vaultKey() async throws -> VaultKeyRecord?
    /// Saves the user's first vault key.
    ///
    /// - Returns: `false` if a master password already exists, such as one set
    ///   up on another device.
    func createVaultKey(_ body: VaultKeyRequestBody) async throws -> Bool
    /// Replaces the vault key after a master password change or reset.
    func replaceVaultKey(_ body: VaultKeyRequestBody) async throws

    // MARK: - Subscription and account

    /// Fetches whether a subscription is required and whether the user has one.
    func subscription() async throws -> SubscriptionStatus
    /// Links an App Store purchase to the user.
    func linkSubscription(transactionID: String) async throws -> SubscriptionStatus
    /// Deletes the account and all its data.
    ///
    /// - Parameters:
    ///   - appleAuthorizationCode: A code the server uses to revoke the user's
    ///     Sign in with Apple tokens, if available.
    ///   - proof: The master password proof, once a master password is set up.
    func deleteAccount(appleAuthorizationCode: String?, proof: String?) async throws
}
