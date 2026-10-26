#if os(iOS)
import SwiftUI

/// iOS lock screen: the artwork fills the screen, the unlock actions sit on a
/// glass card at the bottom.
struct LockView: View {
    var body: some View {
        Color.clear
            .safeAreaBar(edge: .bottom) {
                LockPanel()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Color.clear
                    .overlay {
                        Image(DesignKit.Asset.lockArtwork)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .ignoresSafeArea()
            }
            .colorScheme(.dark)
    }
}

#endif
