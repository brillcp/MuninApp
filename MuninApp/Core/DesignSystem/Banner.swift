import SwiftUI

/// A glass banner with a message on the leading edge and actions on the
/// trailing edge, shown at the bottom of a list.
struct Banner<Message: View, Actions: View>: View {
    /// The message, usually a label.
    @ViewBuilder let message: Message
    /// The buttons on the trailing edge.
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            message
                .font(.callout)
            Spacer()
            actions
        }
        .padding(DesignKit.Spacing.Primitive.s12)
        .glassPanel()
        .padding(DesignKit.Spacing.Primitive.s12)
    }
}
