import SwiftUI

/// A row that shows a card's name and the last four digits of its number.
struct CardRow: View {
    /// The card's name.
    let name: String
    /// The last four digits of the card number.
    let lastDigits: String

    var body: some View {
        #if os(iOS)
        let spacing: CGFloat = DesignKit.Spacing.Primitive.s16
        let vertical: CGFloat = DesignKit.Spacing.Primitive.s6
        #else
        let spacing: CGFloat = DesignKit.Spacing.Primitive.s12
        let vertical: CGFloat = DesignKit.Spacing.Primitive.s8
        #endif
        HStack(spacing: spacing) {
            Image(systemName: DesignKit.Icon.cards)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: DesignKit.Spacing.Primitive.s40)
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
                Text(name)
                    .fontWeight(.semibold)
                if !lastDigits.isEmpty {
                    Text(verbatim: "•••• \(lastDigits)")
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, vertical)
    }
}
