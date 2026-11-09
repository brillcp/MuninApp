import Foundation
import Observation

/// The user's vault preferences, stored in user defaults.
@Observable
final class VaultSettings {
    private static let biometricsKey = "munin.biometrics.enabled"
    private static let autoLockKey = "munin.autoLock.timeout"

    private let defaults: UserDefaults

    /// A Boolean value that indicates whether the user allows biometric unlock.
    var isBiometricUnlockEnabled: Bool {
        didSet { defaults.set(isBiometricUnlockEnabled, forKey: Self.biometricsKey) }
    }
    /// How long the app can stay inactive before the vault locks.
    var autoLockTimeout: AutoLockTimeout {
        didSet { defaults.set(autoLockTimeout.rawValue, forKey: Self.autoLockKey) }
    }

    /// Creates settings backed by the given user defaults.
    ///
    /// Biometric unlock defaults to on, and auto-lock to five minutes.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isBiometricUnlockEnabled = defaults.object(forKey: Self.biometricsKey) as? Bool ?? true
        autoLockTimeout = (defaults.object(forKey: Self.autoLockKey) as? Int).flatMap(AutoLockTimeout.init(rawValue:)) ?? .fiveMinutes
    }
}
