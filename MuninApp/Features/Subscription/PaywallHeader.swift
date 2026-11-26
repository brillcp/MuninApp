import SwiftUI

/// A view that shows the paywall's header.
///
/// The header describes the subscription and, when relevant, shows a billing
/// issue with a button to manage the subscription, or the error from the last
/// purchase or restore.
struct PaywallHeader: View {
    /// The subscription state, which provides the billing issue and the
    /// last error.
    @Environment(SubscriptionManager.self) private var subscriptions
    /// A Boolean value that indicates whether subscription management is open.
    @State private var isManagingSubscription = false

    var body: some View {
        VStack(spacing: DesignKit.Spacing.Primitive.s12) {
            AppIcon(size: 128)
            Text("subscription.title")
                .font(.largeTitle.weight(.semibold))
            Text("subscription.message")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if subscriptions.status?.billingIssue == true {
                Text("subscription.billingIssue")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
                Button("settings.subscription.manage", systemImage: DesignKit.Icon.manageSubscription, action: manageSubscription)
                    .buttonStyle(.glass)
            }
            if let errorMessage = subscriptions.errorMessage {
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
            }
        }
        .padding(DesignKit.Spacing.Primitive.s24)
        .manageSubscriptions(isPresented: $isManagingSubscription)
    }
}

private extension PaywallHeader {
    /// Opens subscription management so the user can update their payment method.
    func manageSubscription() {
        isManagingSubscription = true
    }
}
