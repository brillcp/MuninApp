import CryptoKit
import Foundation

/// RFC 6238 time-based one-time password generation.
extension OTPAccount {
    /// Returns the code valid at the given date.
    ///
    /// - Parameter date: The date to generate the code for.
    /// - Returns: The zero-padded code.
    func code(at date: Date) -> String {
        let counter = UInt64(max(0, date.timeIntervalSince1970)) / UInt64(max(period, 1))
        return hotp(counter: counter)
    }

    /// Returns the number of seconds until the code changes.
    ///
    /// - Parameter date: The current date.
    /// - Returns: The seconds remaining in the code's period.
    func secondsRemaining(at date: Date) -> Int {
        let period = max(self.period, 1)
        return period - Int(UInt64(max(0, date.timeIntervalSince1970)) % UInt64(period))
    }

    /// Returns the RFC 4226 HOTP code for a counter value, zero-padded to
    /// `digits`.
    ///
    /// - Parameter counter: The moving factor, for TOTP the number of periods since the Unix epoch.
    /// - Returns: The zero-padded code.
    func hotp(counter: UInt64) -> String {
        let key = SymmetricKey(data: secret)
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let mac: [UInt8]
        switch algorithm {
        case .sha1:   mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }

        let offset = Int(mac[mac.count - 1] & 0x0f)
        let truncated = UInt32(mac[offset] & 0x7f) << 24
            | UInt32(mac[offset + 1]) << 16
            | UInt32(mac[offset + 2]) << 8
            | UInt32(mac[offset + 3])

        var modulo: UInt32 = 1
        for _ in 0..<min(max(digits, 1), 9) { modulo *= 10 }

        let value = String(truncated % modulo)
        return String(repeating: "0", count: max(0, digits - value.count)) + value
    }
}
