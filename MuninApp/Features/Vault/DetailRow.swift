import SwiftUI

/// A row that shows a field's label above its value, with icon buttons on the
/// trailing edge.
///
/// The caller sets the tap action. While copied, the value briefly reads
/// “Copied”.
struct DetailRow<Value: View, Actions: View>: View {
    let label: LocalizedStringKey
    /// A Boolean value that indicates whether to show “Copied” in place of the value.
    let isCopied: Bool
    @ViewBuilder let value: Value
    /// Icon buttons on the trailing edge.
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s16) {
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Group {
                    if isCopied {
                        Text("global.copied")
                            .foregroundStyle(.tint)
                    } else {
                        value
                    }
                }
                .transition(.blurReplace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignKit.Spacing.Primitive.s16) {
                actions
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .imageScale(.large)
        }
        .padding(.vertical, DesignKit.Spacing.Primitive.s4)
        .contentShape(.rect)
    }
}
