import SwiftUI

/// The lock screen layout for macOS and regular-width iPad windows, with the
/// logo, unlock actions, and version on the left and artwork on the right.
///
/// The unlock actions sit between two spacers, halfway between the logo at
/// the top and the version at the bottom.
struct LockSideBySideLayout: View {
    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s48) {
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s16) {
                LockLogo()
                Spacer()
                LockPanel()
                Spacer()
                LockVersionLabel()
            }
            .padding(DesignKit.Spacing.Primitive.s48)

            LockArtwork()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
