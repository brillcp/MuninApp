#if os(macOS)
import AppKit
import SwiftUI

/// The Munin item in the Mac menu bar.
struct MenuBarContent: View {
    let session: VaultSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("menuBar.open") {
            openWindow(id: MyApp.mainWindowID)
            NSApp.activate()
        }
        Button("lock.command") { session.lock() }
            .keyboardShortcut("l")
        Divider()
        Button("menuBar.quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
#endif
