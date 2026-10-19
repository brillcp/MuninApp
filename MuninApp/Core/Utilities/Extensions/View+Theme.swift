import SwiftUI

extension View {
    /// Bark-coloured toolbar with a light title.
    /// macOS has no API for the window title colour, so the system title is
    /// hidden and drawn as a toolbar item instead.
    func barkToolbar(title: LocalizedStringKey) -> some View {
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
                ToolbarItem(placement: .secondaryAction) {
                    LockToolbarButton()
                }
            }
        #else
        barkNavigationBar()
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    LockToolbarButton()
                }
            }
        #endif
    }

    /// iOS: the navigation bar is Bark with a light, inline (never large) title.
    /// Mac: no change; sheets keep the system look. `title` is unused there.
    @ViewBuilder
    func barkNavigationBar(title: LocalizedStringKey? = nil) -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.bark), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        #else
        self
        #endif
    }
}

/// Locks Munin (same as ⌘L). In the Vault and 2FA toolbars.
private struct LockToolbarButton: View {
    @Environment(VaultSession.self) private var session

    var body: some View {
        Button("lock.command", systemImage: "lock") { session.lock() }
    }
}
