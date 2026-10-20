#if os(iOS)
import SwiftUI

/// iOS lock screen: the artwork fills the screen, the unlock actions sit on a
/// glass card at the bottom.
struct LockView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            
            LockPanel(stacksButtons: false)
            LockVersionLabel()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
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
