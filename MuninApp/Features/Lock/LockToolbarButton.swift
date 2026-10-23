import SwiftUI

/// Locks Munin (same as ⌘L), with a light haptic. In the Vault and 2FA toolbars.
struct LockToolbarButton: View {
    @Environment(VaultSession.self) private var session
    /// Bumped on every tap, to trigger the haptic.
    @State private var taps = 0

    var body: some View {
        Button("lock.command", systemImage: "lock") {
            taps += 1
            session.lock()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}
