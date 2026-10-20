import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// The signed-in user's vault: whether it's set up, locked or unlocked, and the
/// unlocked vault key (in memory only).
///
/// The vault unlocks with Face ID / Touch ID (this device's Keychain copy of
/// the key) or with the master password (which unwraps the key Munin stores).
/// A forgotten master password is reset with the recovery key.
@Observable
final class VaultSession {
    /// Where the vault is in its lifecycle.
    enum State: Equatable {
        /// Asking Munin whether a vault key exists.
        case checking
        /// Choose a master password: first setup, or a reset after the recovery key.
        case needsMasterPassword
        /// Munin has data but no master password is set up, and this device
        /// has no key (data from before master passwords). Paste the recovery key.
        case missingKey
        /// A vault key exists and needs unlocking.
        case locked
        /// The vault key is in memory.
        case unlocked
        /// Munin couldn't be reached or answered with an error.
        case failed(String)
    }

    /// The shortest master password accepted.
    static let minimumPasswordLength = 8

    /// The current state.
    private(set) var state: State = .checking
    /// The unlocked vault key and proof, while unlocked.
    private(set) var vault: UnlockedVault?
    /// True while a slow operation (key derivation, a request) is running.
    private(set) var isWorking = false
    /// The last error, shown on the lock screen or in Settings.
    private(set) var errorMessage: String?

    /// Set once after a brand-new vault is created, to show the recovery key.
    var newRecoveryKey: NewRecoveryKey?

    /// A newly created recovery key, presented as a sheet item.
    struct NewRecoveryKey: Identifiable {
        /// The recovery key, formatted for the user to write down.
        let key: String
        var id: String { key }
    }

    /// Choosing a new master password after unlocking with the recovery key.
    var isResettingMasterPassword: Bool { resetProof != nil }

    /// Whether this device has Face ID or Touch ID set up.
    var canUseBiometrics: Bool {
        biometricsOverride ?? LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Previews only: the canvas and most simulators have no Face ID / Touch ID.
    private let biometricsOverride: Bool?

    /// Creates a session in the checking state.
    ///
    /// - Parameter biometricsAvailable: For previews: overrides whether Face ID
    ///   / Touch ID is available. Nil asks the device.
    init(biometricsAvailable: Bool? = nil) {
        biometricsOverride = biometricsAvailable
    }

    /// The Settings switch. A preference only (UserDefaults); the key itself is in the Keychain.
    ///
    /// Off removes this device's copy of the key; on saves it (while unlocked).
    var isBiometricUnlockEnabled = UserDefaults.standard.object(forKey: VaultSession.biometricsDefaultsKey) as? Bool ?? true {
        didSet {
            guard isBiometricUnlockEnabled != oldValue else { return }
            UserDefaults.standard.set(isBiometricUnlockEnabled, forKey: Self.biometricsDefaultsKey)
            guard let vault else { return }
            if isBiometricUnlockEnabled {
                VaultKeyStore.saveForBiometrics(vault)
            } else {
                VaultKeyStore.deleteBiometric(userID: vault.userID)
            }
        }
    }
    /// UserDefaults key for `isBiometricUnlockEnabled`.
    private static let biometricsDefaultsKey = "munin.biometrics.enabled"

    /// The Settings picker. A preference only (UserDefaults). See `View.autoLock(_:)`.
    var autoLockTimeout: AutoLockTimeout = (UserDefaults.standard.object(forKey: VaultSession.autoLockDefaultsKey) as? Int)
        .flatMap(AutoLockTimeout.init(rawValue:)) ?? .fiveMinutes {
        didSet { UserDefaults.standard.set(autoLockTimeout.rawValue, forKey: Self.autoLockDefaultsKey) }
    }
    /// UserDefaults key for `autoLockTimeout`.
    private static let autoLockDefaultsKey = "munin.autoLock.timeout"

    /// The lock screen shows "Unlock with biometrics" only when this is true.
    var offersBiometricUnlock: Bool { canUseBiometrics && isBiometricUnlockEnabled }

    /// The signed-in user's ID.
    private var userID: String?
    /// The wrapped vault key from Munin.
    private var record: VaultKeyRecord?
    /// The vault key waiting for a master password (new, legacy or recovered).
    private var pendingKey: SymmetricKey?
    /// True when `pendingKey` is a brand-new key, so its recovery key is shown once saved.
    private var isNewVault = false
    /// Recovery key proof, for PUT /v1/vault-key when resetting.
    private var resetProof: String?

    // MARK: - Startup

    /// Works out the vault's state for the signed-in user.
    ///
    /// Locked when Munin has a vault key. Otherwise a master password is needed,
    /// either for this device's legacy key or for a brand-new key when the
    /// account has no data yet. With data but no key anywhere, the recovery
    /// key is asked for. Signing out deletes this device's biometric copy of
    /// the previous user's key.
    func prepare(auth: AuthManager) async {
        let previousUserID = userID
        clear()
        guard auth.isSignedIn, let userID = auth.userID else {
            // Signed out: remove this device's biometric copy of the key.
            if let previousUserID { VaultKeyStore.deleteBiometric(userID: previousUserID) }
            return
        }
        self.userID = userID
        state = .checking
        do {
            let service = MuninService(tokenProvider: auth.tokenProvider)
            if let record = try await service.vaultKey() {
                self.record = record
                state = .locked
            } else if let legacyKey = VaultKeyStore.loadLegacy(userID: userID) {
                pendingKey = legacyKey
                state = .needsMasterPassword
            } else if try await service.entries().isEmpty, try await service.passwords().isEmpty {
                pendingKey = SymmetricKey(size: .bits256)
                isNewVault = true
                state = .needsMasterPassword
            } else {
                state = .missingKey
            }
        } catch is CancellationError {
            return
        } catch where Task.isCancelled {
            return
        } catch let error where error.isMuninAuthRejection {
            auth.signOut()
        } catch {
            state = .failed(error.muninDescription)
        }
    }

    /// Restores a vault from before master passwords, where the recovery key
    /// is the vault key itself. Returns false if the recovery key is invalid.
    func restoreLegacyKey(_ recoveryString: String) -> Bool {
        guard let key = VaultKeyStore.key(fromRecoveryString: recoveryString) else { return false }
        pendingKey = key
        state = .needsMasterPassword
        return true
    }

    // MARK: - Master password setup / reset

    /// Wraps the pending vault key with `password` and saves it to Munin, then unlocks.
    ///
    /// Creates the vault key on first setup, or replaces it when resetting
    /// with the recovery key. If another device set up a master password in
    /// the meantime, it goes to the lock screen instead.
    func setMasterPassword(_ password: String, auth: AuthManager) async {
        guard let userID, let key = pendingKey, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let (body, proof) = try await Self.makeVaultKeyBody(key: key, password: password, userID: userID, currentProof: resetProof)
            let service = MuninService(tokenProvider: auth.tokenProvider)
            if resetProof != nil {
                try await service.replaceVaultKey(body)
            } else if !(try await service.createVaultKey(body)) {
                // Set up on another device in the meantime: unlock with that password.
                errorMessage = Localized("masterPassword.exists")
                record = try await service.vaultKey()
                pendingKey = nil
                state = .locked
                return
            }

            record = VaultKeyRecord(passwordWrappedKey: body.passwordWrappedKey, recoveryWrappedKey: body.recoveryWrappedKey, kdf: body.kdf)
            VaultKeyStore.deleteLegacy(userID: userID)
            if isNewVault { newRecoveryKey = NewRecoveryKey(key: VaultKeyStore.recoveryString(for: key)) }
            pendingKey = nil
            resetProof = nil
            isNewVault = false
            finishUnlock(UnlockedVault(userID: userID, key: key, proof: proof))
        } catch let error where error.isMuninAuthRejection {
            auth.signOut()
        } catch {
            errorMessage = error.muninDescription
        }
    }

    /// Settings ▸ Change Master Password: rewraps the vault key with `new`.
    ///
    /// Checks `current` locally first, then sends its proof so Munin accepts
    /// the change. Returns true when saved.
    func changeMasterPassword(current: String, new: String, auth: AuthManager) async -> Bool {
        guard state == .unlocked, let vault, let record, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let parameters = try JSONDecoder().decode(KDFParameters.self, from: Data(record.kdf.utf8))
            let currentKeys = try await Self.derive(password: current, parameters: parameters)
            guard (try? MasterKey.unwrap(record.passwordWrappedKey, with: currentKeys.wrappingKey, userID: vault.userID, purpose: .password)) != nil else {
                errorMessage = Localized("lock.wrongMasterPassword")
                return false
            }
            let (body, proof) = try await Self.makeVaultKeyBody(key: vault.key, password: new, userID: vault.userID, currentProof: currentKeys.proof)
            try await MuninService(tokenProvider: auth.tokenProvider).replaceVaultKey(body)

            self.record = VaultKeyRecord(passwordWrappedKey: body.passwordWrappedKey, recoveryWrappedKey: body.recoveryWrappedKey, kdf: body.kdf)
            let updated = UnlockedVault(userID: vault.userID, key: vault.key, proof: proof)
            self.vault = updated
            if offersBiometricUnlock { VaultKeyStore.saveForBiometrics(updated) }
            return true
        } catch let error where error.isMuninAuthRejection {
            auth.signOut()
            return false
        } catch {
            errorMessage = error.muninDescription
            return false
        }
    }

    /// Clears the last error.
    func clearError() {
        errorMessage = nil
    }

    /// Back to the lock screen without resetting the master password.
    func cancelReset() {
        pendingKey = nil
        resetProof = nil
        errorMessage = nil
        state = .locked
    }

    // MARK: - Unlock

    /// Unlocks with this device's Keychain copy of the key, behind Face ID / Touch ID.
    func unlockWithBiometrics() async {
        guard state == .locked, let userID, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let reason = Localized("lock.reason")
        let result = await Task.detached(priority: .userInitiated) {
            VaultKeyStore.loadWithBiometrics(userID: userID, reason: reason)
        }.value
        switch result {
        case .unlocked(let vault):
            finishUnlock(vault, saveForBiometrics: false)
        case .notAvailable:
            errorMessage = Localized("lock.biometrics.notSetUp")
        case .canceled:
            break
        case .failed:
            errorMessage = Localized("lock.biometrics.failed")
        }
    }

    /// Unlocks by deriving a key from the master password and unwrapping the
    /// vault key with it. A wrong password fails to unwrap.
    func unlock(masterPassword: String) async {
        guard state == .locked, let userID, let record, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let parameters = try JSONDecoder().decode(KDFParameters.self, from: Data(record.kdf.utf8))
            let keys = try await Self.derive(password: masterPassword, parameters: parameters)
            guard let key = try? MasterKey.unwrap(record.passwordWrappedKey, with: keys.wrappingKey, userID: userID, purpose: .password) else {
                errorMessage = Localized("lock.wrongMasterPassword")
                return
            }
            finishUnlock(UnlockedVault(userID: userID, key: key, proof: keys.proof))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Checks the recovery key, then asks for a new master password.
    func unlock(recoveryKey recoveryString: String) {
        guard state == .locked, let userID, let record else { return }
        guard let key = VaultKeyStore.key(fromRecoveryString: recoveryString) else {
            errorMessage = Localized("vaultKey.missing.invalid")
            return
        }
        let keys = MasterKey.derive(recoveryKey: key)
        guard let unwrapped = try? MasterKey.unwrap(record.recoveryWrappedKey, with: keys.wrappingKey, userID: userID, purpose: .recovery),
              unwrapped.withUnsafeBytes({ Data($0) }) == key.withUnsafeBytes({ Data($0) }) else {
            errorMessage = Localized("vaultKey.missing.invalid")
            return
        }
        errorMessage = nil
        pendingKey = key
        resetProof = keys.proof
        state = .needsMasterPassword
    }

    // MARK: - Lock

    /// Locks the vault: drops the key from memory, clears the icon cache and
    /// any copied password. The vault screens go away with it.
    func lock() {
        guard state == .unlocked else { return }
        vault = nil
        Task { await WebsiteIconStore.shared.clear() }
        Pasteboard.clearSensitive()
        errorMessage = nil
        state = .locked
    }

    // MARK: - Private

    /// Keeps the unlocked vault and, unless told not to, saves this device's
    /// biometric copy of the key.
    private func finishUnlock(_ vault: UnlockedVault, saveForBiometrics: Bool = true) {
        if saveForBiometrics, offersBiometricUnlock {
            VaultKeyStore.saveForBiometrics(vault)
        }
        self.vault = vault
        errorMessage = nil
        state = .unlocked
    }

    /// Resets everything to the checking state, before preparing for a user.
    private func clear() {
        Task { await WebsiteIconStore.shared.clear() }
        state = .checking
        vault = nil
        userID = nil
        record = nil
        pendingKey = nil
        resetProof = nil
        isNewVault = false
        errorMessage = nil
        newRecoveryKey = nil
    }

    /// Wraps `key` with a new master password (fresh salt) and with the recovery key.
    ///
    /// - Returns: The request body and the new password proof.
    private static func makeVaultKeyBody(key: SymmetricKey, password: String, userID: String, currentProof: String?) async throws -> (VaultKeyRequestBody, String) {
        let parameters = KDFParameters.new()
        let passwordKeys = try await derive(password: password, parameters: parameters)
        let recoveryKeys = MasterKey.derive(recoveryKey: key)
        let body = VaultKeyRequestBody(
            passwordWrappedKey: try MasterKey.wrap(key, with: passwordKeys.wrappingKey, userID: userID, purpose: .password),
            recoveryWrappedKey: try MasterKey.wrap(key, with: recoveryKeys.wrappingKey, userID: userID, purpose: .recovery),
            kdf: String(decoding: try JSONEncoder().encode(parameters), as: UTF8.self),
            passwordProof: passwordKeys.proof,
            recoveryProof: recoveryKeys.proof,
            currentProof: currentProof
        )
        return (body, passwordKeys.proof)
    }

    /// Derives the wrapping key and proof from a master password, off the main
    /// actor: PBKDF2 is slow on purpose.
    private static func derive(password: String, parameters: KDFParameters) async throws -> DerivedKeys {
        try await Task.detached(priority: .userInitiated) {
            try MasterKey.derive(password: password, parameters: parameters)
        }.value
    }
}
