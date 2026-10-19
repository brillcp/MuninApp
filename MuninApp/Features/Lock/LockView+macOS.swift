#if os(macOS)
import SwiftUI

/// Mac lock screen: logo, unlock actions and version on the left, artwork on the right.
struct LockView: View {
    var body: some View {
        HStack(spacing: 48) {
            VStack(alignment: .leading, spacing: 16) {
                LockLogo()
                Spacer()
                LockUnlockSection()
                LockVersionLabel()
            }
            .padding(48)

            LockArtwork()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// Right-hand panel. Add the image to the "LockArtwork" image set.
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
