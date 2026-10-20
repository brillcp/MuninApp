import CryptoKit
import Foundation
import Security

/// Nonce for Sign in with Apple, binding Apple's identity token to this sign-in.
enum Nonce {
    /// A cryptographically random nonce, hex-encoded.
    static func random(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The hex-encoded SHA-256 of `string`, the form Apple expects in the request.
    static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
