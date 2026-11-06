import Observation
import SwiftUI

/// An object that lets a command ask a screen to focus its search field.
///
/// A model is used instead of a closure because closures in focused values
/// can't be compared and so invalidate on every update. The screen that owns
/// the search field observes ``count`` and focuses the field when it changes.
@Observable
final class SearchFocusRequest {
    /// A counter incremented on every request; observers react to the change, not the value.
    private(set) var count = 0
}

extension SearchFocusRequest {
    /// Asks the owning screen to focus its search field.
    func request() { count += 1 }
}

extension FocusedValues {
    /// The search focus request of the focused screen, used by Find (⌘F).
    @Entry var searchFocusRequest: SearchFocusRequest?
}

/// Commands that add Edit ▸ Find (⌘F) to focus the current screen's search field.
///
/// The command is disabled when the focused screen has no search field.
struct FindCommands: Commands {
    /// The focused screen's search focus request, if it has a search field.
    @FocusedValue(\.searchFocusRequest) private var searchFocusRequest

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("search.find") { searchFocusRequest?.request() }
                .keyboardShortcut("f")
                .disabled(searchFocusRequest == nil)
        }
    }
}
