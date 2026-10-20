import SwiftUI

/// Adds a Lock command (⌘L) after the app's settings item.
///
/// Available from the Mac menu bar and from a hardware keyboard on iPad.
struct LockCommands: Commands {
    /// The session to lock.
    let session: VaultSession

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("lock.command", systemImage: "lock") { session.lock() }
                .keyboardShortcut("l")
        }
    }
}
