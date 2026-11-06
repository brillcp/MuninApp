import Foundation
import SwiftUI

// MARK: - Localization

/// Returns a localized string, with arguments substituted into its format placeholders.
///
/// - Parameters:
///   - key: The key in the app's string tables.
///   - args: Values for the string's format placeholders.
/// - Returns: The localized, formatted string, or `key` if no translation exists.
nonisolated func Localized(_ key: String, _ args: CVarArg...) -> String {
    formattedLocalizedString(key, args)
}

/// Returns a localized, formatted string as a `LocalizedStringKey` for SwiftUI views.
///
/// See ``Localized(_:_:)``.
nonisolated func LocalizedKey(_ key: String, _ args: CVarArg...) -> LocalizedStringKey {
    LocalizedStringKey(formattedLocalizedString(key, args))
}

/// Formats a localized string with the current locale, so numbers use the
/// user's digits and plural rules select the correct form.
nonisolated private func formattedLocalizedString(_ key: String, _ args: [CVarArg]) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return String(format: format, locale: .current, arguments: args)
}
