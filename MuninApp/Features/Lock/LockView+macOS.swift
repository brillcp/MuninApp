#if os(macOS)
import SwiftUI

/// Mac lock screen: logo, unlock actions and version on the left, artwork on the right.
struct LockView: View {
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

/// The artwork on the right of the Mac lock screen, from the "munin" image set.
private struct LockArtwork: View {
    var body: some View {
        Image("munin")
            .resizable()
            .scaledToFit()
    }
}

#Preview("Biometrics") {
    LockView()
        .environment(VaultSession(biometricsAvailable: true))
        .environment(AuthManager())
}

#Preview("Master password") {
    LockView()
        .environment(VaultSession(biometricsAvailable: false))
        .environment(AuthManager())
}
#endif
