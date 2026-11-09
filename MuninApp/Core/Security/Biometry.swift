import Foundation
import LocalAuthentication

/// The device's Face ID or Touch ID capability.
nonisolated struct Biometry: Equatable, Sendable {
    /// A Boolean value that indicates whether Face ID or Touch ID is set up.
    let isAvailable: Bool
    /// A Boolean value that indicates whether the device uses Face ID rather than Touch ID.
    let usesFaceID: Bool

    /// Reads the current capability from the system.
    ///
    /// Creating an `LAContext` isn't free, so read this when the app becomes
    /// active rather than on every view update.
    static func current() -> Biometry {
        let context = LAContext()
        let isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return Biometry(isAvailable: isAvailable, usesFaceID: context.biometryType == .faceID)
    }
}
