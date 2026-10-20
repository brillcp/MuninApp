import Foundation

/// Random passwords from the system's cryptographically secure generator.
struct PasswordGenerator {
    /// Characters per password.
    var length = 20
    /// Include A–Z.
    var useCapitals = true
    /// Include 0–9.
    var useDigits = true
    /// Include symbols.
    var useSymbols = true

    /// Always included.
    static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
    /// Included when `useCapitals` is on.
    static let capitals = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    /// Included when `useDigits` is on.
    static let digits = Array("0123456789")
    /// Included when `useSymbols` is on.
    static let symbols = Array("@!$%&*")

    /// The enabled character sets.
    private var sets: [[Character]] {
        var sets = [Self.lowercase]
        if useCapitals { sets.append(Self.capitals) }
        if useDigits { sets.append(Self.digits) }
        if useSymbols { sets.append(Self.symbols) }
        return sets
    }

    /// A new random password, with at least one character from every enabled set.
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

    /// `length` as a Double, for a Slider.
    var sliderLength: Double {
        get { Double(length) }
        set { length = Int(newValue) }
    }

    /// Bits of entropy for the current settings.
    var entropy: Double {
        Double(length) * log2(Double(sets.reduce(0) { $0 + $1.count }))
    }
}
