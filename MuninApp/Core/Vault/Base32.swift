import Foundation

/// RFC 4648 Base32, the format authenticator secrets come in.
/// Case-insensitive; ignores padding, spaces and dashes.
enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let lookup: [Character: UInt8] = {
        var table: [Character: UInt8] = [:]
        for (index, character) in alphabet.enumerated() { table[character] = UInt8(index) }
        return table
    }()

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
