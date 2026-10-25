import Foundation

/// RFC 4648 Base32, the format authenticator secrets come in.
/// Case-insensitive; ignores padding, spaces and dashes.
enum Base32 {
    /// The 32 symbols, in value order.
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    /// Each symbol's 5-bit value.
    private static let lookup: [Character: UInt8] = {
        var table: [Character: UInt8] = [:]
        for (index, character) in alphabet.enumerated() { table[character] = UInt8(index) }
        return table
    }()

    /// Encodes data as Base32 without padding, the form `otpauth` links use.
    static func encode(_ data: Data) -> String {
        var buffer: UInt32 = 0
        var bitCount = 0
        var output = ""

        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                output.append(alphabet[Int((buffer >> UInt32(bitCount)) & 31)])
            }
        }
        if bitCount > 0 {
            output.append(alphabet[Int((buffer << UInt32(5 - bitCount)) & 31)])
        }
        return output
    }

    /// Decodes a Base32 string. Nil if it contains other characters or decodes to nothing.
    static func decode(_ string: String) -> Data? {
        var buffer: UInt32 = 0
        var bitCount = 0
        var output = Data()

        for character in string.uppercased() where !"= -".contains(character) {
            guard let value = lookup[character] else { return nil }
            buffer = (buffer << 5) | UInt32(value)
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                output.append(UInt8(truncatingIfNeeded: buffer >> UInt32(bitCount)))
            }
        }
        return output.isEmpty ? nil : output
    }
}
