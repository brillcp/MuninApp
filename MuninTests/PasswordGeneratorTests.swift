import Foundation
@testable import MuninApp
import Testing

@Suite("PasswordGenerator")
struct PasswordGeneratorTests {
    @Test("Generates the requested length", arguments: [8, 20, 64])
    func length(_ length: Int) {
        #expect(PasswordGenerator(length: length).generate().count == length)
    }

    @Test("Includes at least one character from every enabled set")
    func everySet() {
        for _ in 0..<200 {
            let password = PasswordGenerator(length: 4).generate()
            #expect(password.contains(where: PasswordGenerator.lowercase.contains))
            #expect(password.contains(where: PasswordGenerator.capitals.contains))
            #expect(password.contains(where: PasswordGenerator.digits.contains))
            #expect(password.contains(where: PasswordGenerator.symbols.contains))
        }
    }

    @Test("Uses only the enabled sets")
    func onlyEnabledSets() {
        let generator = PasswordGenerator(length: 200, useCapitals: false, useDigits: true, useSymbols: false)
        let allowed = Set(PasswordGenerator.lowercase + PasswordGenerator.digits)
        #expect(generator.generate().allSatisfy(allowed.contains))
    }

    @Test("Never returns fewer characters than enabled sets")
    func minimumLength() {
        #expect(PasswordGenerator(length: 0).generate().count == 4)
        #expect(PasswordGenerator(length: 1, useCapitals: false, useDigits: false, useSymbols: false).generate().count == 1)
    }

    @Test("Produces different passwords")
    func random() {
        let generator = PasswordGenerator()
        #expect(Set((0..<20).map { _ in generator.generate() }).count == 20)
    }

    @Test("Computes entropy from length and pool size")
    func entropy() {
        let lowercaseOnly = PasswordGenerator(length: 10, useCapitals: false, useDigits: false, useSymbols: false)
        #expect(abs(lowercaseOnly.entropy - 10 * log2(26)) < 0.0001)
        // 26 + 26 + 10 + 6 = 68 characters.
        #expect(abs(PasswordGenerator(length: 20).entropy - 20 * log2(68)) < 0.0001)
    }

    @Test("Maps the slider value to a whole length")
    func sliderLength() {
        var generator = PasswordGenerator()
        generator.sliderLength = 32.7
        #expect(generator.length == 32)
        #expect(generator.sliderLength == 32)
    }
}
