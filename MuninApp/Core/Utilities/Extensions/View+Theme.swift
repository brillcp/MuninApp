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
            // The sidebar always shows.
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .cancellationAction) {
                    LockToolbarButton()
                }
            }
        #else
        barkNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
            .toolbarColorScheme(.dark, for: .navigationBar)
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

extension View {
    /// Mac: a floating, rounded glass panel over the window's Valhall
    /// background. Content inside should hide its own scroll background.
    /// iOS: unchanged.
    @ViewBuilder
    func glassPanel() -> some View {
        #if os(macOS)
        clipShape(.rect(cornerRadius: 16))
            // Tinted with the window background colour, partly see-through.
            .glassEffect(.regular.tint(Color.panelTint.opacity(0.4)), in: .rect(cornerRadius: 16))
            .padding(8)
        #else
        self
        #endif
    }
}

#if os(macOS)
extension Color {
    /// The window background colour (light or dark with the system). Tints the
    /// glass panels and, more lightly, the Valhall background.
    static let panelTint = Color(nsColor: .windowBackgroundColor)
}
#endif
