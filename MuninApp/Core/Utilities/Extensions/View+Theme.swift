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
            }
        #else
        barkNavigationBar()
        #endif
    }

    /// iOS: every navigation bar is Bark with a light, inline (never large)
    /// title. Mac sheets have no navigation bar, so nothing changes there.
    @ViewBuilder
    func barkNavigationBar() -> some View {
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
