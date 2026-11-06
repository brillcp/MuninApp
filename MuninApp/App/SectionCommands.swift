import SwiftUI

extension FocusedValues {
    /// A binding to the main window's selected sidebar section.
    @Entry var mainSection: Binding<MainView.Section>?
}

/// Menu commands that switch the main window's section.
///
/// Adds View ▸ Vault (⌘1) and View ▸ 2FA (⌘2). The commands are disabled
/// while the main window isn't focused or the vault is locked.
struct SectionCommands: Commands {
    /// The focused main window's section, or `nil` if no main window is focused.
    @FocusedValue(\.mainSection) private var section

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button("main.tab.vault") { section?.wrappedValue = .vault }
                .keyboardShortcut("1")
                .disabled(section == nil)
            Button("main.tab.codes") { section?.wrappedValue = .twoFactor }
                .keyboardShortcut("2")
                .disabled(section == nil)
            Divider()
        }
    }
}
