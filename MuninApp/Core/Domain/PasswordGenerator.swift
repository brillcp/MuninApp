import Foundation

/// A generator of random passwords that uses the system's cryptographically
/// secure random number generator.
struct PasswordGenerator {
    /// The number of characters in each password.
    var length = 20
    /// A Boolean value that indicates whether to include uppercase letters.
    var useCapitals = true
    /// A Boolean value that indicates whether to include digits.
    var useDigits = true
    /// A Boolean value that indicates whether to include symbols.
    var useSymbols = true

    /// Lowercase letters, always included.
    static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
    /// Uppercase letters, included when `useCapitals` is true.
    static let capitals = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    /// Digits, included when `useDigits` is true.
    static let digits = Array("0123456789")
    /// Symbols, included when `useSymbols` is true.
    static let symbols = Array("@!$%&*")

    /// The enabled character sets.
    private var sets: [[Character]] {
        var sets = [Self.lowercase]
        if useCapitals { sets.append(Self.capitals) }
        if useDigits { sets.append(Self.digits) }
        if useSymbols { sets.append(Self.symbols) }
        return sets
    }

    /// Generates a random password.
    ///
    /// - Returns: A password with at least one character from every enabled
    ///   character set.
    func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        let sets = sets
        let pool = sets.flatMap { $0 }
        var characters = sets.map { $0.randomElement(using: &rng)! }
        while characters.count < max(length, sets.count) {
            characters.append(pool.randomElement(using: &rng)!)
        }
        characters.shuffle(using: &rng)
        return String(characters.prefix(max(length, sets.count)))
    }

    /// The length as a `Double`, for binding to a slider.
    var sliderLength: Double {
        get { Double(length) }
        set { length = Int(newValue) }
    }

    /// The password's entropy in bits for the current settings.
    var entropy: Double {
        Double(length) * log2(Double(sets.reduce(0) { $0 + $1.count }))
    }
}
