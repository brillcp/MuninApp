import Foundation
@testable import MuninApp
import Testing

@Suite("Base32")
struct Base32Tests {
    /// RFC 4648 section 10 test vectors, without padding.
    nonisolated static let vectors: [(String, String)] = [
        ("f", "MY"),
        ("fo", "MZXQ"),
        ("foo", "MZXW6"),
        ("foob", "MZXW6YQ"),
        ("fooba", "MZXW6YTB"),
        ("foobar", "MZXW6YTBOI"),
    ]

    @Test("Encodes RFC 4648 test vectors", arguments: vectors)
    func encode(plain: String, encoded: String) {
        #expect(Base32.encode(Data(plain.utf8)) == encoded)
    }

    @Test("Decodes RFC 4648 test vectors", arguments: vectors)
    func decode(plain: String, encoded: String) {
        #expect(Base32.decode(encoded) == Data(plain.utf8))
    }

    @Test("Ignores padding, case, spaces and hyphens", arguments: [
        "MZXW6===", "mzxw6", "MZX W6", "mzx-w6", "Mz Xw-6 ===",
    ])
    func lenientDecoding(_ input: String) {
        #expect(Base32.decode(input) == Data("foo".utf8))
    }

    @Test("Encodes the empty input as an empty string")
    func encodeEmpty() {
        #expect(Base32.encode(Data()).isEmpty)
    }

    @Test("Rejects empty and invalid input", arguments: ["", "===", "MZXW1", "MZXW0", "MZXW8", "MZ!W6"])
    func invalid(_ input: String) {
        #expect(Base32.decode(input) == nil)
    }

    @Test("Round-trips arbitrary bytes")
    func roundTrip() {
        for length in 1...40 {
            let data = Data((0..<length).map { _ in UInt8.random(in: .min ... .max) })
            #expect(Base32.decode(Base32.encode(data)) == data)
        }
    }
}
