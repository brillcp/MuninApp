import SwiftUI

/// A view that shows the card list's error, empty, loading, and no-results states.
struct CardsEmptyState: View {
    /// The error to show when loading failed.
    let errorMessage: String?
    /// A Boolean value that indicates whether there are no cards.
    let isEmpty: Bool
    /// A Boolean value that indicates whether the first load has finished.
    let hasLoaded: Bool
    /// The search text that matched nothing, if any.
    let searchText: String?
    /// The action that the Try Again button performs.
    let onRetry: () -> Void

    var body: some View {
        if let errorMessage {
            LoadErrorView(message: errorMessage, systemImage: DesignKit.Icon.warning, onRetry: onRetry)
        } else if isEmpty {
            if hasLoaded {
                ContentUnavailableView("cards.empty.title", systemImage: DesignKit.Icon.cards)
            } else {
                AccentSpinner(size: DesignKit.Spacing.Primitive.s24)
            }
        } else if let searchText {
            ContentUnavailableView.search(text: searchText)
        }
    }
}
