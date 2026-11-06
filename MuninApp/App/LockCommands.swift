import SwiftUI

/// Commands that add a Lock item (⌘L) after the app's settings item.
///
/// The command is available from the macOS menu bar and from a hardware
/// keyboard on iPad.
struct LockCommands: Commands {
    /// The session to lock.
    let session: VaultSession

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("lock.command", systemImage: DesignKit.Icon.lock, action: session.lock)
                .keyboardShortcut("l")
        }
    }
}
