import SwiftUI

/// A row that shows a password item's website icon, name, and username.
struct AutoFillPasswordRow: View {
    /// The item to show.
    let item: PasswordItem
    /// The action that fills the password.
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: DesignKit.Spacing.Primitive.s12) {
                WebsiteIcon(url: item.url, size: DesignKit.Spacing.Primitive.s32)
                VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
                    Text(item.name)
                    if !item.username.isEmpty {
                        Text(item.username)
                            #if os(iOS)
                            .font(.subheadline)
                            #endif
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
