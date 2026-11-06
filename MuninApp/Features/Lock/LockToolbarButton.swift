import SwiftUI

/// A toolbar button that locks the vault, like ⌘L, with a light haptic.
struct LockToolbarButton: View {
    @Environment(VaultSession.self) private var session
    /// A counter incremented on every tap to trigger the haptic.
    @State private var taps = 0

    var body: some View {
        Button("lock.command", systemImage: DesignKit.Icon.lock) {
            taps += 1
            session.lock()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}
