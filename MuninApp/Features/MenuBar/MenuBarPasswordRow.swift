#if os(macOS)
import SwiftUI

/// A row in the menu bar list showing a password's icon, name, username, and
/// copy buttons.
struct MenuBarPasswordRow: View {
    let item: PasswordItem
    /// The field just copied from this row, if any.
    let copiedField: Field?
    let onCopyUsername: () -> Void
    let onCopyPassword: () -> Void

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            WebsiteIcon(url: item.url, size: DesignKit.Spacing.Primitive.s24)
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
                Text(item.name)
                    .lineLimit(1)
                if !item.username.isEmpty {
                    Text(item.username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if copiedField != nil {
                Text("global.copied")
                    .font(.caption)
                    .foregroundStyle(.accent)
            }
            Button("menuBar.copyUsername", systemImage: DesignKit.Icon.username, action: onCopyUsername)
                .help(Text("menuBar.copyUsername"))
                .disabled(item.username.isEmpty)
            Button("vault.copyPassword", systemImage: DesignKit.Icon.password, action: onCopyPassword)
                .help(Text("vault.copyPassword"))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(height: DesignKit.Spacing.Primitive.s48)
    }
}

extension MenuBarPasswordRow {
    /// A field that can be copied from the row.
    enum Field { case username, password }
}
#endif
