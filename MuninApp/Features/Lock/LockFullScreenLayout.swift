#if os(iOS)
import SwiftUI

/// A lock screen layout with full-screen artwork and the unlock actions on a glass card at the bottom.
///
/// Used on iPhone, and on iPad in a compact-width window.
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
