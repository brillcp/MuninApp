import SwiftUI

/// What ⌘F does on the current screen. Equatable so the focused value doesn't
/// invalidate the menu on every update (a bare closure isn't comparable). Two
/// actions count as equal: there's one search screen, and its closure only
/// sets that screen's focus state, so an older copy does the same thing.
struct FindAction: Equatable {
    let perform: () -> Void

    static func == (lhs: FindAction, rhs: FindAction) -> Bool { true }
}

extension FocusedValues {
    /// Set by the screen with the search field; ⌘F calls it.
    @Entry var findAction: FindAction?
}

/// Edit ▸ Find (⌘F) moves focus to the current screen's search field.
struct FindCommands: Commands {
    @FocusedValue(\.findAction) private var findAction

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("search.find") { findAction?.perform() }
                .keyboardShortcut("f")
                .disabled(findAction == nil)
        }
    }
}
