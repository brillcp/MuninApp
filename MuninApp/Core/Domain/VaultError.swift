import Foundation

/// An error from a vault operation that requires a signed-in user and an unlocked key.
enum VaultError: LocalizedError {
    /// No user is signed in.
    case notSignedIn
    /// The vault is locked, so its key isn't available.
    case keyMissing

    /// A localized message describing the error.
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return Localized("errors.notSignedIn")
        case .keyMissing:  return Localized("errors.keyMissing")
        }
    }
}
