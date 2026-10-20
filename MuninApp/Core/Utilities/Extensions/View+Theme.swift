import SwiftUI

extension View {
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
            }
        #else
        barkNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    LockToolbarButton()
                }
            }
        #endif
    }

    @ViewBuilder
    func barkNavigationBar(title: LocalizedStringKey? = nil) -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.bark.opacity(0.9), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        #else
        self
        #endif
    }
}

/// Locks Munin (same as ⌘L). In the Vault and 2FA toolbars.
struct LockToolbarButton: View {
    @Environment(VaultSession.self) private var session
    @State private var taps = 0

    var body: some View {
        Button("lock.command", systemImage: "lock") {
            taps += 1
            session.lock()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}
