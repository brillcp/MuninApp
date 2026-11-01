import Foundation

/// Unlocking from the lock screen, with the password list fetched alongside.
///
/// The encrypted passwords start downloading when an unlock begins (Face ID
/// / Touch ID tapped, or the master password submitted), so they're usually
/// there the moment it succeeds. They're only decrypted once the vault is
/// unlocked; if the unlock fails or is cancelled, the download is dropped.
extension VaultSession {
    /// Face ID / Touch ID, while the password list downloads.
    func unlockWithBiometrics(prefetchingInto vaultModel: VaultViewModel, auth: AuthManager) async {
        vaultModel.prefetch(auth: auth)
        await unlockWithBiometrics()
        if state != .unlocked { vaultModel.discardPrefetch() }
    }

    /// The master password, while the password list downloads.
    func unlock(masterPassword: String, prefetchingInto vaultModel: VaultViewModel, auth: AuthManager) async {
        vaultModel.prefetch(auth: auth)
        await unlock(masterPassword: masterPassword)
        if state != .unlocked { vaultModel.discardPrefetch() }
    }
}
