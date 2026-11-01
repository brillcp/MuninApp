#if os(iOS)
import SwiftUI

/// The lock screen on iPhone, and on iPad in a narrow window (Split View,
/// Slide Over): the artwork fills the screen, the unlock actions sit on a
/// glass card at the bottom, with buttons the card's full width.
struct LockFullScreenLayout: View {
    var body: some View {
        Color.clear
            .safeAreaBar(edge: .bottom) {
                LockPanel()
                    .glassEffect(in: .rect(cornerRadius: DesignKit.Spacing.Primitive.s24))
                    .buttonSizing(.flexible)
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
