import SwiftUI

/// A banner shown during the billing grace period.
///
/// The App Store couldn't renew the subscription, but the app remains fully
/// functional during the grace period. The Manage Subscription button lets
/// the user update their payment method.
struct BillingIssueBanner: View {
    /// A Boolean value that indicates whether subscription management is open.
    @State private var isManagingSubscription = false

    var body: some View {
        Banner {
            Label("subscription.gracePeriod", systemImage: DesignKit.Icon.billingIssue)
                .foregroundStyle(.orange)
        } actions: {
            Button("subscription.updatePayment", action: manageSubscription)
                .buttonStyle(.glass)
        }
        .manageSubscriptions(isPresented: $isManagingSubscription)
    }
}

private extension BillingIssueBanner {
    /// Opens subscription management so the user can update their payment method.
    func manageSubscription() {
        isManagingSubscription = true
    }
}
