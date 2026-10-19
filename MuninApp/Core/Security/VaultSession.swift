import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// The signed-in user's vault: whether it's set up, locked or unlocked, and the
/// unlocked key (in memory only). Replaces the old Face ID-only app lock.
///
/// Unlock with Face ID / Touch ID (this device's Keychain copy) or the master
/// password (unwraps the key Munin stores). A forgotten master password is
/// reset with the recovery key.
@Observable
final class VaultSession {
    enum State: Equatable {
        case checking
        /// Choose a master password: first setup, or a reset after the recovery key.
        case needsMasterPassword
        /// Munin has data but no master password is set up, and this device
        /// has no key (before master passwords). Paste the recovery key.
        case missingKey
        case locked
        case unlocked
        case failed(String)
    }

    static let minimumPasswordLength = 8

    private(set) var state: State = .checking
    private(set) var vault: UnlockedVault?
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    
    /// Set once after a brand-new vault is created, to show the recovery key.
    var newRecoveryKey: String?

    /// Choosing a new master password after unlocking with the recovery key.
    var isResettingMasterPassword: Bool { resetProof != nil }

    var canUseBiometrics: Bool {
        biometricsOverride ?? LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Previews only: the canvas and most simulators have no Face ID / Touch ID.
    private let biometricsOverride: Bool?

    init(biometricsAvailable: Bool? = nil) {
        biometricsOverride = biometricsAvailable
    }

    /// The Settings switch. A preference only (UserDefaults); the key itself is in the Keychain.
    private(set) var isBiometricUnlockEnabled = UserDefaults.standard.object(forKey: VaultSession.biometricsDefaultsKey) as? Bool ?? true
    private static let biometricsDefaultsKey = "munin.biometrics.enabled"

    /// The lock screen shows "Unlock with biometrics" only when this is true.
    var offersBiometricUnlock: Bool { canUseBiometrics && isBiometricUnlockEnabled }

    private var userID: String?
    private var record: VaultKeyRecord?
    /// The vault key waiting for a master password (new, legacy or recovered).
    private var pendingKey: SymmetricKey?
    private var isNewVault = false
    /// Recovery key proof, for PUT /v1/vault-key when resetting.
    private var resetProof: String?

    // MARK: - Startup

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

    /// Before master passwords: the recovery key is the vault key itself.
    func restoreLegacyKey(_ recoveryString: String) -> Bool {
        guard let key = VaultKeyStore.key(fromRecoveryString: recoveryString) else { return false }
        pendingKey = key
        state = .needsMasterPassword
        return true
    }

    // MARK: - Master password setup / reset

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
            if isNewVault { newRecoveryKey = VaultKeyStore.recoveryString(for: key) }
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

    /// Settings → Change Master Password. Returns true when saved.
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

    /// Settings → biometrics switch. Off removes this device's copy of the key.
    func setBiometricUnlock(_ enabled: Bool) {
        isBiometricUnlockEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.biometricsDefaultsKey)
        guard let vault else { return }
        if enabled {
            VaultKeyStore.saveForBiometrics(vault)
        } else {
            VaultKeyStore.deleteBiometric(userID: vault.userID)
        }
    }

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

    /// ⌘L / menu bar. Drops the key from memory; the vault screens go away with it.
    func lock() {
        guard state == .unlocked else { return }
        vault = nil
        errorMessage = nil
        state = .locked
    }

    // MARK: - Private

    private func finishUnlock(_ vault: UnlockedVault, saveForBiometrics: Bool = true) {
        if saveForBiometrics, offersBiometricUnlock {
            VaultKeyStore.saveForBiometrics(vault)
        }
        self.vault = vault
        errorMessage = nil
        state = .unlocked
    }

    private func clear() {
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
    /// Returns the request body and the new password proof.
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

    /// PBKDF2 is slow on purpose; keep it off the main actor.
    private static func derive(password: String, parameters: KDFParameters) async throws -> DerivedKeys {
        try await Task.detached(priority: .userInitiated) {
            try MasterKey.derive(password: password, parameters: parameters)
        }.value
    }
}
