import SwiftUI
import StoreKit

/// Shown at the bottom of the Vault and 2FA screens during the billing grace
/// period: the App Store couldn't renew the subscription, but everything still
/// works for now. Manage Subscription leads to updating the payment method.
struct BillingIssueBanner: View {
    @Environment(\.openURL) private var openURL
    /// iOS: shows the App Store's Manage Subscriptions sheet.
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
    /// Opens subscription management: the system sheet on iOS, the App Store page on Mac.
    func manageSubscription() {
        #if os(iOS)
        isManagingSubscription = true
        #else
        openURL(AppLinks.manageSubscriptions)
        #endif
    }
}
