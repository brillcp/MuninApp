import CryptoKit
import Foundation
import Security

/// Nonce generation for Sign in with Apple.
///
/// The nonce binds Apple's identity token to a single sign-in request.
enum Nonce {
    /// Generates a cryptographically random, hex-encoded nonce.
    ///
    /// - Parameter byteCount: The number of random bytes before encoding.
    /// - Returns: A hex string twice as long as `byteCount`.
    static func random(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the hex-encoded SHA-256 hash of a string, as Apple expects in the
    /// authorization request.
    ///
    /// - Parameter string: The string to hash, typically a nonce.
    /// - Returns: The lowercase hex digest.
    static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
