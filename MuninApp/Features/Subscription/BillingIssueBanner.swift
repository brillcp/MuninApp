import StoreKit
import SwiftUI

/// A banner shown during the billing grace period.
///
/// The App Store couldn't renew the subscription, but the app remains fully
/// functional during the grace period. The Manage Subscription button lets
/// the user update their payment method.
struct BillingIssueBanner: View {
    @Environment(\.openURL) private var openURL
    /// A Boolean value that indicates whether the Manage Subscriptions sheet is
    /// presented (iOS).
    @State private var isManagingSubscription = false

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            Label("subscription.gracePeriod", systemImage: DesignKit.Icon.billingIssue)
                .font(.callout)
                .foregroundStyle(.orange)
            Spacer()
            Button("subscription.updatePayment", action: manageSubscription)
                .buttonStyle(.glass)
        }
        .padding(DesignKit.Spacing.Primitive.s12)
        .glassEffect(in: .rect(cornerRadius: DesignKit.Spacing.Primitive.s16))
        .padding(DesignKit.Spacing.Primitive.s12)
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        #endif
    }
}

private extension BillingIssueBanner {
    /// Opens subscription management: the system sheet on iOS, or the App Store
    /// page on macOS.
    func manageSubscription() {
        #if os(iOS)
        isManagingSubscription = true
        #else
        openURL(AppLinks.manageSubscriptions)
        #endif
    }
}
