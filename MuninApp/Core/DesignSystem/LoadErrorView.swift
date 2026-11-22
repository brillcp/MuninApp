import SwiftUI

/// A view that explains why a list couldn't load, with a Try Again button.
struct LoadErrorView: View {
    /// The reason loading failed.
    let message: String
    /// The SF Symbol name shown above the title.
    let systemImage: String
    /// The action that the Try Again button performs.
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("errors.loadVault.title", systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("global.tryAgain", action: onRetry)
        }
    }
}
