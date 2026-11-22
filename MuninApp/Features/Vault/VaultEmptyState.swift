import SwiftUI

/// A view that shows the vault's error, empty, loading, and no-results states.
struct VaultEmptyState: View {
    /// The error to show when loading failed.
    let errorMessage: String?
    /// A Boolean value that indicates whether the vault has no passwords.
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
                ContentUnavailableView("vault.empty.title", systemImage: DesignKit.Icon.vault)
            } else {
                ProgressView()
                    .tint(.primary)
            }
        } else if let searchText {
            ContentUnavailableView.search(text: searchText)
        }
    }
}
