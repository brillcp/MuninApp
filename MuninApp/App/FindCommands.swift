import Observation
import SwiftUI

/// A screen's request to focus its search field.
///
/// This is a model rather than a closure: closures in focused values (even
/// wrapped in a struct) can't be compared, so they invalidate on every update.
/// The screen with the search field watches `count` and focuses its field
/// whenever it changes.
@Observable
final class SearchFocusRequest {
    /// Incremented on every request. Observers react to the change, not the value.
    private(set) var count = 0

    /// Asks the screen that owns this request to focus its search field.
    func request() { count += 1 }
}

extension FocusedValues {
    /// Published by the screen that has a search field; ⌘F uses it to focus that field.
    @Entry var searchFocusRequest: SearchFocusRequest?
}

/// Adds Edit ▸ Find (⌘F), which moves focus to the current screen's search field.
///
/// The command is disabled when the focused screen has no search field.
struct FindCommands: Commands {
    /// The focused screen's request, if it has a search field.
    @FocusedValue(\.searchFocusRequest) private var searchFocusRequest

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("search.find") { searchFocusRequest?.request() }
                .keyboardShortcut("f")
                .disabled(searchFocusRequest == nil)
        }
    }
}
