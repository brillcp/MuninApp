import SwiftUI

/// A view that presents the lock screen, from sign-in through unlock.
///
/// On macOS and in a regular-width iPad window, the logo and unlock actions
/// appear beside the artwork. On iPhone and in a compact-width iPad window,
/// the artwork fills the screen and the actions sit on a card at the bottom.
/// Because the layout follows the horizontal size class, it adapts to Split
/// View and Slide Over.
struct LockView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .regular {
            LockSideBySideLayout()
        } else {
            LockFullScreenLayout()
        }
        #else
        LockSideBySideLayout()
        #endif
    }
}
