import SwiftUI

/// A numbered step in the setup guide.
struct AutoFillStepRow: View {
    /// The step's one-based number.
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignKit.Spacing.Primitive.s12) {
            Text(verbatim: "\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: DesignKit.Spacing.Primitive.s24)
            Text(text)
        }
    }
}
