import SwiftUI

/// A view that shows the error, empty, and loading states of the codes list.
struct TwoFactorEmptyState: View {
    /// The load error, or `nil` if loading succeeded.
    let errorMessage: String?
    /// A Boolean value that indicates whether there are no accounts.
    let isEmpty: Bool
    /// A Boolean value that indicates whether the first load has finished.
    ///
    /// A spinner shows until then.
    let hasLoaded: Bool
    /// The action that the Try Again button performs.
    let onRetry: () -> Void
    /// The action that the Add Account button performs.
    let onAdd: () -> Void

    var body: some View {
        if let errorMessage {
            LoadErrorView(message: errorMessage, systemImage: DesignKit.Icon.offline, onRetry: onRetry)
        } else if isEmpty {
            if hasLoaded {
                ContentUnavailableView {
                    Label("codes.empty.title", systemImage: DesignKit.Icon.noAccounts)
                } description: {
                    Text("codes.empty.message")
                }
                .padding(.horizontal, DesignKit.Spacing.Primitive.s32)
            } else {
                AccentSpinner(size: DesignKit.Spacing.Primitive.s24)
            }
        }
    }
}
