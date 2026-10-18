import Foundation
import SwiftUI

// MARK: - Localization

/// Looks up `key` in Localizable.strings and substitutes any `args` into its stored format placeholders.
/// Falls back to `key` itself if missing.
nonisolated func Localized(_ key: String, _ args: CVarArg...) -> String {
    formattedLocalizedString(key, args)
}

nonisolated func LocalizedKey(_ key: String, _ args: CVarArg...) -> LocalizedStringKey {
    LocalizedStringKey(formattedLocalizedString(key, args))
}

/// Formats with the current locale so numbers use the user's digits and
/// entries in Localizable.stringsdict pick the right plural form.
nonisolated private func formattedLocalizedString(_ key: String, _ args: [CVarArg]) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return String(format: format, locale: .current, arguments: args)
}
