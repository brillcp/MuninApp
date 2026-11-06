import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// An object that manages the signed-in user's vault: its setup, lock state,
/// and the unlocked vault key.
///
/// The vault key is held in memory only while unlocked. The vault unlocks with
/// Face ID or Touch ID, using this device's Keychain copy of the key, or with
/// the master password, which unwraps the key stored on the server. A
/// forgotten master password is reset with the recovery key.
@Observable
final class VaultSession {
    /// The user defaults key for ``isBiometricUnlockEnabled``.
    private static let biometricsDefaultsKey = "munin.biometrics.enabled"
    /// The user defaults key for ``autoLockTimeout``.
    private static let autoLockDefaultsKey = "munin.autoLock.timeout"

    /// The shortest master password accepted.
    static let minimumPasswordLength = 8

    /// An override for biometric availability, used by previews and simulators.
    private let biometricsOverride: Bool?
    private var userID: String?
    /// The wrapped vault key fetched from the server.
    private var record: VaultKeyRecord?
    /// A vault key awaiting a master password: new, legacy, or recovered.
    private var pendingKey: SymmetricKey?
    /// A Boolean value that indicates whether ``pendingKey`` is newly
    /// generated, so its recovery key is shown once saved.
    private var isNewVault = false
    /// The recovery key proof that authorizes replacing the vault key during a reset.
    private var resetProof: String?
    /// The in-flight request for the wrapped vault key, started by
    /// ``prepare(auth:)``. A master password unlock awaits it if needed.
    private var recordFetch: Task<VaultKeyRecord?, any Error>?

    /// The current lifecycle state.
    private(set) var state: State = .checking
    /// The vault key and password proof, available while unlocked.
    private(set) var vault: UnlockedVault?
    /// A Boolean value that indicates whether a long-running operation, such
    /// as key derivation or a network request, is in progress.
    private(set) var isWorking = false
    /// The most recent error message, shown on the lock screen or in Settings.
    private(set) var errorMessage: String?

    /// The recovery key for a newly created vault, set once so it can be shown to the user.
    var newRecoveryKey: NewRecoveryKey?

    /// A Boolean value that indicates whether the user allows biometric unlock.
    ///
    /// The preference is stored in user defaults; the key itself lives in the
    /// Keychain. Turning it off deletes this device's copy of the key, and
    /// turning it on while unlocked saves one.
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

    /// How long the app can stay inactive before the vault locks.
    ///
    /// Stored in user defaults. See ``SwiftUI/View/autoLock(_:)``.
    var autoLockTimeout: AutoLockTimeout = (UserDefaults.standard.object(forKey: VaultSession.autoLockDefaultsKey) as? Int)
        .flatMap(AutoLockTimeout.init(rawValue:)) ?? .fiveMinutes {
        didSet { UserDefaults.standard.set(autoLockTimeout.rawValue, forKey: Self.autoLockDefaultsKey) }
    }

    /// Creates a session in the checking state.
    ///
    /// - Parameter biometricsAvailable: Overrides whether Face ID or Touch ID
    ///   is available, for previews. Pass `nil` to ask the device.
    init(biometricsAvailable: Bool? = nil) {
        biometricsOverride = biometricsAvailable
    }
}

extension VaultSession {
    /// The stages of the vault's lifecycle.
    enum State: Equatable {
        /// The session is asking the server whether a vault key exists.
        case checking
        /// The user needs to choose a master password, either during first
        /// setup or after unlocking with the recovery key.
        case needsMasterPassword
        /// The account has data but no stored vault key, and this device has
        /// no local copy of the key. The user needs to enter the recovery key.
        case missingKey
        /// A vault key exists and the vault is locked.
        case locked
        /// The vault key is in memory.
        case unlocked
        /// The server couldn't be reached or returned an error.
        case failed(String)
    }

    /// A newly created recovery key, presented as a sheet item.
    struct NewRecoveryKey: Identifiable {
        /// The recovery key, formatted for the user to write down.
        let key: String
        var id: String { key }
    }

    /// The reason the vault couldn't be opened, in the ``State/failed(_:)`` state.
    ///
    /// Drives the lock screen's failure alert. The setter is a no-op so the
    /// property can back an alert binding; the alert's actions retry or sign
    /// out, which leave the failed state.
    var failureMessage: String? {
        get {
            if case .failed(let message) = state { message } else { nil }
        }
        set { } // swiftlint:disable:this unused_setter_value
    }

    /// A Boolean value that indicates whether the user is choosing a new
    /// master password after unlocking with the recovery key.
    var isResettingMasterPassword: Bool { resetProof != nil }

    /// A Boolean value that indicates whether Face ID or Touch ID is set up on this device.
    var canUseBiometrics: Bool {
        biometricsOverride ?? LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// A Boolean value that indicates whether this device uses Face ID rather
    /// than Touch ID, used to choose labels and icons.
    var usesFaceID: Bool {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID
    }

    /// A Boolean value that indicates whether the lock screen offers biometric unlock.
    var offersBiometricUnlock: Bool { canUseBiometrics && isBiometricUnlockEnabled }

    // MARK: - Startup

    /// Determines the vault's state for the signed-in user.
    ///
    /// The vault is locked when the server has a vault key. Otherwise the user
    /// needs a master password, either for this device's legacy key or for a
    /// new key when the account has no data. If the account has data but no
    /// key exists anywhere, the user is asked for the recovery key. When no
    /// user is signed in, the previous user's biometric key copy is deleted.
    ///
    /// When this device has a biometric copy of the key, the lock screen
    /// appears immediately and the server is queried in the background. If the
    /// server rejects the session, the user is signed out; if it has no vault
    /// key, the session moves to the setup state it needs.
    ///
    /// - Parameter auth: The authentication manager for the signed-in user.
    func prepare(auth: AuthManager) async {
        let previousUserID = userID
        clear()
        guard auth.isSignedIn, let userID = auth.userID else {
            if let previousUserID { VaultKeyStore.deleteBiometric(userID: previousUserID) }
            return
        }
        self.userID = userID
        let unlocksWithoutMunin = offersBiometricUnlock && VaultKeyStore.hasBiometric(userID: userID)
        state = unlocksWithoutMunin ? .locked : .checking
        do {
            let service = MuninService(tokenProvider: auth.tokenProvider)
            let fetch = Task { try await service.vaultKey() }
            recordFetch = fetch
            if let record = try await fetch.value {
                self.record = record
                if state == .checking { state = .locked }
                return
            }
            // Without a server key, a vault unlocked from the local copy is stale.
            vault = nil
            if let legacyKey = VaultKeyStore.loadLegacy(userID: userID) {
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
            // An already unlocked vault stays open; its lists report their own errors.
            if state != .unlocked { state = .failed(error.muninDescription) }
        }
    }

    /// Restores a legacy vault, whose recovery key is the vault key itself.
    ///
    /// - Parameter recoveryString: The recovery key the user entered.
    /// - Returns: `false` if the recovery key is invalid.
    func restoreLegacyKey(_ recoveryString: String) -> Bool {
        guard let key = VaultKeyStore.key(fromRecoveryString: recoveryString) else { return false }
        pendingKey = key
        state = .needsMasterPassword
        return true
    }

    // MARK: - Master password setup / reset

    /// Wraps the pending vault key with a master password, saves it to the
    /// server, and unlocks.
    ///
    /// Creates the vault key on first setup, or replaces it when resetting with
    /// the recovery key. If another device has already set up a master
    /// password, the session moves to the locked state instead.
    ///
    /// - Parameters:
    ///   - password: The new master password.
    ///   - auth: The authentication manager for the signed-in user.
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
                // Another device created the key first; unlock with its password.
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

    /// Rewraps the vault key with a new master password.
    ///
    /// Verifies the current password locally, then sends its proof so the
    /// server accepts the change.
    ///
    /// - Parameters:
    ///   - current: The current master password.
    ///   - new: The new master password.
    ///   - auth: The authentication manager for the signed-in user.
    /// - Returns: `true` if the change was saved.
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

    /// Clears the most recent error message.
    func clearError() {
        errorMessage = nil
    }

    /// Cancels a master password reset and returns to the locked state.
    func cancelReset() {
        pendingKey = nil
        resetProof = nil
        errorMessage = nil
        state = .locked
    }

    // MARK: - Unlock

    /// Unlocks with this device's Keychain copy of the key, protected by Face ID or Touch ID.
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
    /// vault key with it.
    ///
    /// Waits for the wrapped key if its request is still in flight. A wrong
    /// password fails to unwrap and sets ``errorMessage``.
    ///
    /// - Parameter masterPassword: The master password the user entered.
    func unlock(masterPassword: String) async {
        guard state == .locked, let userID, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        if self.record == nil, let recordFetch {
            self.record = try? await recordFetch.value
        }
        guard let record, state == .locked else { return }
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

    /// Verifies the recovery key, then moves to the state for choosing a new master password.
    ///
    /// - Parameter recoveryString: The recovery key the user entered.
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

    /// Locks the vault, removing the key from memory and clearing the icon
    /// cache and any copied password.
    func lock() {
        guard state == .unlocked else { return }
        vault = nil
        Task { await WebsiteIconStore.shared.clear() }
        Pasteboard.clearSensitive()
        errorMessage = nil
        state = .locked
    }
}

private extension VaultSession {
    /// Stores the unlocked vault and optionally saves a biometric copy of its key.
    func finishUnlock(_ vault: UnlockedVault, saveForBiometrics: Bool = true) {
        if saveForBiometrics, offersBiometricUnlock {
            VaultKeyStore.saveForBiometrics(vault)
        }
        self.vault = vault
        errorMessage = nil
        state = .unlocked
    }

    /// Resets the session to the checking state.
    func clear() {
        Task { await WebsiteIconStore.shared.clear() }
        state = .checking
        vault = nil
        userID = nil
        record = nil
        recordFetch = nil
        pendingKey = nil
        resetProof = nil
        isNewVault = false
        errorMessage = nil
        newRecoveryKey = nil
    }

    /// Wraps a vault key with a new master password, using a fresh salt, and
    /// with the recovery key.
    ///
    /// - Returns: The request body and the new password proof.
    static func makeVaultKeyBody(key: SymmetricKey, password: String, userID: String, currentProof: String?) async throws -> (VaultKeyRequestBody, String) {
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

    /// Derives the wrapping key and proof from a master password.
    ///
    /// Runs off the main actor because PBKDF2 is deliberately slow.
    static func derive(password: String, parameters: KDFParameters) async throws -> DerivedKeys {
        try await Task.detached(priority: .userInitiated) {
            try MasterKey.derive(password: password, parameters: parameters)
        }.value
    }
}
