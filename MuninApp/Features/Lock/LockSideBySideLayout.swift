import SwiftUI

/// The lock screen on the Mac and in a full-width iPad window: logo, unlock
/// actions and version on the left, artwork on the right.
struct LockSideBySideLayout: View {
    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s48) {
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s16) {
                LockLogo()
                Spacer()
                LockPanel()
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

/// The artwork on the right of the lock screen.
private struct LockArtwork: View {
    var body: some View {
        Image(DesignKit.Asset.lockArtwork)
            .resizable()
            .scaledToFit()
    }
}
