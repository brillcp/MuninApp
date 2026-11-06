import SwiftUI

/// The artwork on the trailing side of the lock screen.
struct LockArtwork: View {
    var body: some View {
        Image(DesignKit.Asset.lockArtwork)
            .resizable()
            .scaledToFit()
    }
}
