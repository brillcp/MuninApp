import Foundation
@testable import MuninApp
import Testing

@Suite("TOTP")
struct TOTPTests {
    /// A test vector from RFC 6238, Appendix B.
    nonisolated struct Vector: Sendable, CustomTestStringConvertible {
        let time: TimeInterval
        let algorithm: OTPAccount.Algorithm
        let code: String
        var testDescription: String { "\(algorithm.rawValue) @ \(Int(time))" }
    }

    nonisolated static let rfc6238Vectors: [Vector] = [
        (59, ["94287082", "46119246", "90693936"]),
        (1_111_111_109, ["07081804", "68084774", "25091201"]),
        (1_111_111_111, ["14050471", "67062674", "99943326"]),
        (1_234_567_890, ["89005924", "91819424", "93441116"]),
        (2_000_000_000, ["69279037", "90698825", "38618901"]),
        (20_000_000_000, ["65353130", "77737706", "47863826"]),
    ].flatMap { time, codes in
        zip([OTPAccount.Algorithm.sha1, .sha256, .sha512], codes).map { Vector(time: time, algorithm: $0, code: $1) }
    }

    static func secret(for algorithm: OTPAccount.Algorithm) -> Data {
        switch algorithm {
        case .sha1: Data("12345678901234567890".utf8)
        case .sha256: Data("12345678901234567890123456789012".utf8)
        case .sha512: Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)
        }
    }

    @Test("RFC 6238 test vectors", arguments: rfc6238Vectors)
    func rfc6238(_ vector: Vector) {
        let account = OTPAccount(issuer: "", name: "", secret: Self.secret(for: vector.algorithm), digits: 8, period: 30, algorithm: vector.algorithm)
        #expect(account.code(at: Date(timeIntervalSince1970: vector.time)) == vector.code)
    }

    @Test("RFC 4226 HOTP test vectors", arguments: Array([
        "755224", "287082", "359152", "969429", "338314",
        "254676", "287922", "162583", "399871", "520489",
    ].enumerated()))
    func rfc4226(counter: Int, code: String) {
        let account = OTPAccount(issuer: "", name: "", secret: Self.secret(for: .sha1))
        #expect(account.hotp(counter: UInt64(counter)) == code)
    }

    @Test("Codes have the configured number of digits, zero-padded")
    func digits() {
        for digits in [6, 7, 8] {
            let account = OTPAccount(issuer: "", name: "", secret: Self.secret(for: .sha1), digits: digits)
            #expect(account.code(at: Date(timeIntervalSince1970: 1_111_111_109)).count == digits)
        }
        // RFC 6238 gives 07081804 at this time; the leading zero must survive.
        let account = OTPAccount(issuer: "", name: "", secret: Self.secret(for: .sha1), digits: 8)
        #expect(account.code(at: Date(timeIntervalSince1970: 1_111_111_109)).hasPrefix("0"))
    }

    @Test("The period sets how often the code changes")
    func period() {
        let account = OTPAccount(issuer: "", name: "", secret: Self.secret(for: .sha1), period: 60)
        #expect(account.code(at: Date(timeIntervalSince1970: 60)) == account.code(at: Date(timeIntervalSince1970: 119)))
        #expect(account.code(at: Date(timeIntervalSince1970: 60)) == account.hotp(counter: 1))
        #expect(account.code(at: Date(timeIntervalSince1970: 120)) == account.hotp(counter: 2))
    }

    @Test("Seconds remaining counts down within each period", arguments: [
        (0.0, 30), (1.0, 29), (29.0, 1), (29.9, 1), (30.0, 30), (59.0, 1),
    ])
    func secondsRemaining(time: TimeInterval, expected: Int) {
        let account = OTPAccount(issuer: "", name: "", secret: Self.secret(for: .sha1))
        #expect(account.secondsRemaining(at: Date(timeIntervalSince1970: time)) == expected)
    }

    @Test("A zero period doesn't crash")
    func zeroPeriod() {
        let account = OTPAccount(issuer: "", name: "", secret: Self.secret(for: .sha1), period: 0)
        #expect(account.code(at: Date(timeIntervalSince1970: 100)).count == 6)
        #expect(account.secondsRemaining(at: Date(timeIntervalSince1970: 100)) == 1)
    }
}
