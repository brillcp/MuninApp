import SwiftUI

/// A row that shows a 2FA account's issuer, name, and current code.
struct AutoFillCodeRow: View {
    let account: OTPAccount
    /// The date used to compute the code, updated every second.
    let date: Date
    /// The action that fills the code.
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: DesignKit.Spacing.Primitive.s12) {
                VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
                    Text(account.title)
                    if let subtitle = account.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(verbatim: account.code(at: date))
                    .font(.title3.monospacedDigit())
                    .contentTransition(.numericText())
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
