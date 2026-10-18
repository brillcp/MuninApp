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
            }
        #else
        toolbarBackground(Color(.bark), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
    }
}
