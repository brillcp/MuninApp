import Foundation

/// Unlock methods that download the password list in parallel.
///
/// The encrypted passwords start downloading when an unlock begins, so they're
/// usually available as soon as it succeeds. They're decrypted only after the
/// vault unlocks. If the unlock fails or is canceled, the download is
/// discarded.
extension VaultSession {
    /// Unlocks with Face ID or Touch ID while downloading the password list.
    ///
    /// - Parameters:
    ///   - vaultModel: The view model that receives the password list.
    ///   - auth: The authentication manager for the download.
    func unlockWithBiometrics(prefetchingInto vaultModel: VaultViewModel, auth: AuthManager) async {
        vaultModel.prefetch(auth: auth)
        await unlockWithBiometrics()
        if state != .unlocked { vaultModel.discardPrefetch() }
    }

    /// Unlocks with the master password while downloading the password list.
    ///
    /// - Parameters:
    ///   - masterPassword: The master password.
    ///   - vaultModel: The view model that receives the password list.
    ///   - auth: The authentication manager for the download.
    func unlock(masterPassword: String, prefetchingInto vaultModel: VaultViewModel, auth: AuthManager) async {
        vaultModel.prefetch(auth: auth)
        await unlock(masterPassword: masterPassword)
        if state != .unlocked { vaultModel.discardPrefetch() }
    }
}
