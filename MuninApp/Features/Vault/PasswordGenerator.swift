import Foundation

/// Random passwords from the system's cryptographically secure generator.
struct PasswordGenerator {
    var length = 20
    var useCapitals = true
    var useDigits = true
    var useSymbols = true

    static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
    static let capitals = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let digits = Array("0123456789")
    static let symbols = Array("@!$%&*")

    private var sets: [[Character]] {
        var sets = [Self.lowercase]
        if useCapitals { sets.append(Self.capitals) }
        if useDigits { sets.append(Self.digits) }
        if useSymbols { sets.append(Self.symbols) }
        return sets
    }

    /// Includes at least one character from every enabled set.
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
