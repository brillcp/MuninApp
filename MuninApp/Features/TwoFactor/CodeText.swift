import SwiftUI

/// A view that shows a two-factor code.
///
/// Equatable, so it redraws only when the code changes or is copied.
struct CodeText: View, Equatable {
    let code: String
    /// A Boolean value that indicates whether to show Copied instead of the code.
    let didCopy: Bool

    var body: some View {
        (didCopy ? Text("global.copied") : Text(verbatim: TwoFactorRow.formatted(code)))
            .font(.system(.title2, design: .monospaced, weight: .semibold))
            .foregroundStyle(didCopy ? .accent : .primary)
            .monospacedDigit()
            .animation(DesignKit.Motion.linear, value: code)
    }
}
