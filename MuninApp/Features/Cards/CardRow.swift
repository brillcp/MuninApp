import SwiftUI

/// A row that shows a card's name and the last four digits of its number.
struct CardRow: View {
    /// The card to display.
    let item: CardItem

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
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s4) {
                Text(item.name)
                if !item.lastDigits.isEmpty {
                    Text(verbatim: "•••• \(item.lastDigits)")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, vertical)
    }
}
