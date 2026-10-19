#if os(iOS)
import SwiftUI

/// iOS lock screen: the artwork fills the screen, the unlock actions sit on a
/// glass card at the bottom.
struct LockView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LockLogo()
            Spacer()
            LockPanel(stacksButtons: true)
            LockVersionLabel()
        }
        .padding()
        // Fill the screen so the background below covers all of it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            // A full-screen frame with the image centred in it. scaledToFill
            // overflows the frame; the overflow is cut evenly on both sides.
            Color.clear
                .overlay {
                    Image("munin")
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .ignoresSafeArea()
        }
        .colorScheme(.dark)
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
