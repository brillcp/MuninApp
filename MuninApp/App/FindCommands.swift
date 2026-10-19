import Observation
import SwiftUI

/// A screen's request to focus its search field. A model rather than a closure:
/// closures in focused values (even wrapped in a struct) can't be compared and
/// invalidate on every update. The screen watches `count` and focuses its field.
@Observable
final class SearchFocusRequest {
    private(set) var count = 0

    func request() { count += 1 }
}

extension FocusedValues {
    /// Set by the screen with the search field; ⌘F calls it.
    @Entry var searchFocusRequest: SearchFocusRequest?
}

/// Edit ▸ Find (⌘F) moves focus to the current screen's search field.
struct FindCommands: Commands {
    @FocusedValue(\.searchFocusRequest) private var searchFocusRequest

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("search.find") { searchFocusRequest?.request() }
                .keyboardShortcut("f")
                .disabled(searchFocusRequest == nil)
        }
    }
}
