import CryptoKit
import Foundation
import Observation

/// An object that manages the signed-in user's vault: its setup, lock state,
/// and the unlocked vault key.
///
/// The vault key is held in memory only while unlocked. The vault unlocks with
/// Face ID or Touch ID, using this device's Keychain copy of the key, or with
/// the master password, which unwraps the key stored on the server. A
/// forgotten master password is reset with the recovery key.
///
/// The session is the lock state machine. Key wrapping lives in
/// ``VaultKeyCrypto``, preferences in ``VaultSettings``, and server calls go
/// through ``MuninAPI``.
@Observable
final class VaultSession {
    /// The shortest master password accepted.
    static let minimumPasswordLength = 8

    private let api: any MuninAPI
    private let user: any UserSession
    /// An override for biometric availability, used by previews and simulators.
    private let biometricsOverride: Bool?
    private var userID: String?
    /// The wrapped vault key fetched from the server.
    private var record: VaultKeyRecord?
    /// A vault key awaiting a master password: new or recovered.
    private var pendingKey: SymmetricKey?
    /// A Boolean value that indicates whether ``pendingKey`` is newly
    /// generated, so its recovery key is shown once saved.
    private var isNewVault = false
    /// The recovery key proof that authorizes replacing the vault key during a reset.
    private var resetProof: String?
    /// The in-flight request for the wrapped vault key, started by
    /// ``prepare()``. A master password unlock awaits it if needed.
    private var recordFetch: Task<VaultKeyRecord?, any Error>?
    /// The device's Face ID or Touch ID capability, refreshed by ``refreshBiometry()``.
    private var biometry = Biometry.current()

    /// The current lifecycle state.
    private(set) var state: State = .checking
    /// The vault key and password proof, available while unlocked.
    private(set) var vault: UnlockedVault?
    /// A Boolean value that indicates whether a long-running operation, such
    /// as key derivation or a network request, is in progress.
    private(set) var isWorking = false
    /// The most recent error message, shown on the lock screen or in Settings.
    private(set) var errorMessage: String?

    /// The user's vault preferences.
    let settings: VaultSettings

    /// The recovery key for a newly created vault, set once so it can be shown to the user.
    var newRecoveryKey: NewRecoveryKey?

    /// Creates a session in the checking state.
    ///
    /// - Parameters:
    ///   - api: The API that stores the wrapped vault key.
    ///   - user: The signed-in user.
    ///   - settings: The user's vault preferences.
    ///   - biometricsAvailable: Overrides whether Face ID or Touch ID is
    ///     available, for previews. Pass `nil` to ask the device.
    init(api: any MuninAPI, user: any UserSession, settings: VaultSettings = VaultSettings(), biometricsAvailable: Bool? = nil) {
        self.api = api
        self.user = user
        self.settings = settings
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
    var canUseBiometrics: Bool { biometricsOverride ?? biometry.isAvailable }

    /// A Boolean value that indicates whether this device uses Face ID rather
    /// than Touch ID, used to choose labels and icons.
    var usesFaceID: Bool { biometry.usesFaceID }

    /// A Boolean value that indicates whether the lock screen offers biometric unlock.
    var offersBiometricUnlock: Bool { canUseBiometrics && settings.isBiometricUnlockEnabled }

    /// A Boolean value that indicates whether the user allows biometric unlock.
    ///
    /// The preference lives in ``settings``; the key itself lives in the
    /// Keychain. Turning it off deletes this device's copy of the key, and
    /// turning it on while unlocked saves one.
    var isBiometricUnlockEnabled: Bool {
        get { settings.isBiometricUnlockEnabled }
        set {
            guard newValue != settings.isBiometricUnlockEnabled else { return }
            settings.isBiometricUnlockEnabled = newValue
            guard let vault else { return }
            if newValue {
                VaultKeyStore.saveForBiometrics(vault)
            } else {
                VaultKeyStore.deleteBiometric(userID: vault.userID)
            }
        }
    }

    /// How long the app can stay inactive before the vault locks.
    ///
    /// See ``SwiftUI/View/autoLock(_:)``.
    var autoLockTimeout: AutoLockTimeout {
        get { settings.autoLockTimeout }
        set { settings.autoLockTimeout = newValue }
    }

    /// Reads the device's Face ID or Touch ID capability again, for example
    /// when the app becomes active.
    func refreshBiometry() {
        let current = Biometry.current()
        if current != biometry { biometry = current }
    }

    // MARK: - Startup

    /// Determines the vault's state for the signed-in user.
    ///
    /// The vault is locked when the server has a vault key. Otherwise the user
    /// needs a master password for a new key when the account has no data.
    /// Every vault gets its key with its master password, so data without a
    /// key is reported as a failure rather than overwritten. When no
    /// user is signed in, the previous user's biometric key copy is deleted.
    ///
    /// When this device has a biometric copy of the key, the lock screen
    /// appears immediately and the server is queried in the background. If the
    /// server rejects the session, the user is signed out; if it has no vault
    /// key, the session moves to the setup state it needs.
    func prepare() async {
        let previousUserID = userID
        clear()
        guard user.isSignedIn, let userID = user.userID else {
            if let previousUserID { VaultKeyStore.deleteBiometric(userID: previousUserID) }
            return
        }
        self.userID = userID
        let unlocksWithoutMunin = offersBiometricUnlock && VaultKeyStore.hasBiometric(userID: userID)
        state = unlocksWithoutMunin ? .locked : .checking
        do {
            let api = api
            let fetch = Task { try await api.vaultKey() }
            recordFetch = fetch
            if let record = try await fetch.value {
                self.record = record
                if state == .checking { state = .locked }
                return
            }
            // Without a server key, a vault unlocked from the local copy is stale.
            vault = nil
            if try await api.entries().isEmpty, try await api.passwords().isEmpty {
                pendingKey = SymmetricKey(size: .bits256)
                isNewVault = true
                state = .needsMasterPassword
            } else {
                state = .failed(Localized("errors.keyMissing"))
            }
        } catch is CancellationError {
            return
        } catch where Task.isCancelled {
            return
        } catch let error where error.isMuninAuthRejection {
            user.signOut()
        } catch {
            // An already unlocked vault stays open; its lists report their own errors.
            if state != .unlocked { state = .failed(error.muninDescription) }
        }
    }

    // MARK: - Master password setup / reset

    /// Wraps the pending vault key with a master password, saves it to the
    /// server, and unlocks.
    ///
    /// Creates the vault key on first setup, or replaces it when resetting with
    /// the recovery key. If another device has already set up a master
    /// password, the session moves to the locked state instead.
    ///
    /// - Parameter password: The new master password.
    func setMasterPassword(_ password: String) async {
        guard let userID, let key = pendingKey, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let (body, proof) = try await VaultKeyCrypto.makeVaultKeyBody(key: key, password: password, userID: userID, currentProof: resetProof)
            if resetProof != nil {
                try await api.replaceVaultKey(body)
            } else if !(try await api.createVaultKey(body)) {
                // Another device created the key first; unlock with its password.
                errorMessage = Localized("masterPassword.exists")
                record = try await api.vaultKey()
                pendingKey = nil
                state = .locked
                return
            }

            record = VaultKeyCrypto.record(for: body)
            if isNewVault { newRecoveryKey = NewRecoveryKey(key: VaultKeyStore.recoveryString(for: key)) }
            pendingKey = nil
            resetProof = nil
            isNewVault = false
            finishUnlock(UnlockedVault(userID: userID, key: key, proof: proof))
        } catch let error where error.isMuninAuthRejection {
            user.signOut()
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
    /// - Returns: `true` if the change was saved.
    func changeMasterPassword(current: String, new: String) async -> Bool {
        guard state == .unlocked, let vault, let record, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            guard let currentKeys = try await VaultKeyCrypto.verify(record, password: current, userID: vault.userID) else {
                errorMessage = Localized("lock.wrongMasterPassword")
                return false
            }
            let (body, proof) = try await VaultKeyCrypto.makeVaultKeyBody(key: vault.key, password: new, userID: vault.userID, currentProof: currentKeys.proof)
            try await api.replaceVaultKey(body)

            self.record = VaultKeyCrypto.record(for: body)
            let updated = UnlockedVault(userID: vault.userID, key: vault.key, proof: proof)
            self.vault = updated
            if offersBiometricUnlock { VaultKeyStore.saveForBiometrics(updated) }
            return true
        } catch let error where error.isMuninAuthRejection {
            user.signOut()
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
            guard let vault = try await VaultKeyCrypto.unlock(record, password: masterPassword, userID: userID) else {
                errorMessage = Localized("lock.wrongMasterPassword")
                return
            }
            finishUnlock(vault)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Verifies the recovery key, then moves to the state for choosing a new master password.
    ///
    /// - Parameter recoveryString: The recovery key the user entered.
    func unlock(recoveryKey recoveryString: String) {
        guard state == .locked, let userID, let record else { return }
        guard let recovered = VaultKeyCrypto.recover(record, recoveryString: recoveryString, userID: userID) else {
            errorMessage = Localized("lock.recovery.invalid")
            return
        }
        errorMessage = nil
        pendingKey = recovered.key
        resetProof = recovered.proof
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
}
