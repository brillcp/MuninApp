import SwiftUI

extension View {
    /// The main screens' toolbar.
    ///
    /// - macOS: a Bark-coloured window toolbar with the title drawn as a white
    ///   toolbar item. macOS has no API for the window title's colour, so the
    ///   system title is removed. `subtitle` isn't shown.
    /// - iOS: the system navigation title and subtitle, and a Lock button.
    func barkToolbar(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        #if os(macOS)
        toolbarBackground(Color(.bark), for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        #else
        self
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    LockToolbarButton()
                }
            }
        #endif
    }
}

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
