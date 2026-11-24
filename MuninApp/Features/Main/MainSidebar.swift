import SwiftUI

extension EnvironmentValues {
    /// The width that the macOS sidebar covers on the leading edge of the
    /// content behind it, or 0 where there's no floating sidebar.
    ///
    /// Lists extend under the sidebar so their rows show through its glass,
    /// and inset their content and overlays by this width so nothing is
    /// hidden behind it.
    @Entry var sidebarWidth: CGFloat = 0
}

#if os(macOS)

/// The main window's sidebar on macOS: a fixed glass panel, like the password
/// panel, that's always shown and can't be resized or collapsed.
///
/// It lists the vault, 2FA, and cards sections. At the bottom, the user's initials
/// open the Settings window.
struct MainSidebar: View {
    /// The sign-in state, which provides the email the initials come from.
    @Environment(AuthManager.self) private var auth

    /// The panel's width.
    private static let width: CGFloat = 220
    /// The panel's margin from the window's edges.
    private static let margin = DesignKit.Spacing.Primitive.s12

    /// The selected section.
    @Binding var selection: MainView.Section

    var body: some View {
        List(selection: $selection) {
            Section("main.section.munin") {
                SidebarTabLabel(title: "main.tab.vault", systemImage: DesignKit.Icon.vault, isSelected: selection == .vault)
                    .tag(MainView.Section.vault)
                SidebarTabLabel(title: "main.tab.codes", systemImage: DesignKit.Icon.twoFactor, isSelected: selection == .twoFactor)
                    .tag(MainView.Section.twoFactor)
                SidebarTabLabel(title: "main.tab.cards", systemImage: DesignKit.Icon.cards, isSelected: selection == .cards)
                    .tag(MainView.Section.cards)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: DesignKit.Spacing.Primitive.s0) {
            SettingsLink {
                AccountAvatar(email: auth.email, size: DesignKit.Spacing.Primitive.s32)
            }
            .buttonStyle(.plain)
            .help(Text("settings.title"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignKit.Spacing.Primitive.s12)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .glassPanel()
        .padding(Self.margin)
    }
}

extension MainSidebar {
    /// The width the sidebar covers, including its margins, so content
    /// behind it can start after it.
    static var occupiedWidth: CGFloat {
        width + margin * 2
    }
}
#endif
