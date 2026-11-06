import Foundation

/// RFC 4648 Base32 encoding, the format of authenticator secrets.
///
/// Decoding is case-insensitive and ignores padding, spaces, and dashes.
enum Base32 {
    /// The 32 symbols, in order of value.
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    /// The 5-bit value of each symbol.
    private static let lookup: [Character: UInt8] = {
        var table: [Character: UInt8] = [:]
        for (index, character) in alphabet.enumerated() { table[character] = UInt8(index) }
        return table
    }()

    /// Encodes data as Base32 without padding, as `otpauth://` URLs use.
    ///
    /// - Parameter data: The data to encode.
    /// - Returns: The Base32 string.
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

    /// Decodes a Base32 string.
    ///
    /// - Parameter string: The Base32 string to decode.
    /// - Returns: The decoded data, or `nil` if the string contains invalid
    ///   characters or decodes to no data.
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
