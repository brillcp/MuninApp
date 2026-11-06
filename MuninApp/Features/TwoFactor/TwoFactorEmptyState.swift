import SwiftUI

/// A view that shows the error, empty, and loading states of the codes list.
struct TwoFactorEmptyState: View {
    /// The load error, or `nil` if loading succeeded.
    let errorMessage: String?
    let isEmpty: Bool
    /// A Boolean value that indicates whether the first load has finished.
    ///
    /// A spinner shows until then.
    let hasLoaded: Bool
    let onRetry: () -> Void
    let onAdd: () -> Void

    var body: some View {
        if let errorMessage {
            ContentUnavailableView {
                Label("errors.loadVault.title", systemImage: DesignKit.Icon.offline)
            } description: {
                Text(errorMessage)
            } actions: {
                Button("global.tryAgain", action: onRetry)
            }
        } else if isEmpty {
            if hasLoaded {
                ContentUnavailableView {
                    Label("codes.empty.title", systemImage: DesignKit.Icon.noAccounts)
                } description: {
                    Text("codes.empty.message")
                } actions: {
                    Button("codes.empty.add", action: onAdd)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
                    .tint(.primary)
            }
        }
    }
}
