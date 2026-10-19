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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            Image("munin")
                .resizable()
                .scaledToFill()
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
