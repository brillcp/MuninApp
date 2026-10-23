import SwiftUI

extension FocusedValues {
    /// The main window's selected sidebar section; ⌘1 and ⌘2 switch it.
    @Entry var mainSection: Binding<MainView.Section>?
}

/// View ▸ Vault (⌘1) and View ▸ 2FA (⌘2) switch the main window's section.
///
/// Disabled while the main window isn't focused or the vault is locked.
struct SectionCommands: Commands {
    /// The focused main window's section, if it's showing.
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
