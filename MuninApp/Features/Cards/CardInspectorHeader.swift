import SwiftUI

/// The first section of ``CardInspector``: a card icon above the card's name.
struct CardInspectorHeader: View {
    /// The card's name.
    let name: String

    var body: some View {
        Section {
            VStack(spacing: DesignKit.Spacing.Primitive.s16) {
                Image(systemName: DesignKit.Icon.cards)
                    .font(.system(size: DesignKit.Spacing.Primitive.s48))
                    .foregroundStyle(.tint)
                Text(name)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .padding(.vertical, DesignKit.Spacing.Primitive.s8)
        }
    }
}
