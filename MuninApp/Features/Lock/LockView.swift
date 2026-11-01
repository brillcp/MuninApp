import SwiftUI

/// The lock screen, from sign-in through unlock.
///
/// The Mac and a full-width iPad window show it side by side (logo and unlock
/// actions next to the artwork). iPhone, and iPad in a narrow window, show
/// the artwork full screen with the actions on a card at the bottom. The iPad
/// switches by window width, so it follows Split View and Slide Over.
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
