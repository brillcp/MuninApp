import SwiftUI

/// ⌘L locks the app (Mac menu bar, and a hardware keyboard on iPad).
struct LockCommands: Commands {
    let session: VaultSession

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("lock.command", systemImage: "lock") { session.lock() }
                .keyboardShortcut("l")
        }
    }
}
