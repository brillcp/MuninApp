import StoreKit
import SwiftUI

/// The subscription screen: Apple's subscription store for Munin's monthly
/// plan, with its free trial, price and Restore Purchases.
///
/// Shown after setup, and on unlock while the vault is read-only. Closing it
/// keeps the vault read-only. Purchases carry the user's ID as their app
/// account token and are sent to Munin to check with Apple. Closes itself
/// once Munin confirms the subscription.
struct PaywallView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: [SubscriptionManager.productID]) {
            PaywallHeader()
        }
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .subscriptionStorePolicyDestination(url: AppLinks.privacyPolicy, for: .privacyPolicy)
        .subscriptionStorePolicyDestination(url: AppLinks.termsOfUse, for: .termsOfService)
        .inAppPurchaseOptions(purchaseOptions)
        .onInAppPurchaseCompletion(perform: purchaseCompleted)
        .tint(.accent)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }
}

private extension PaywallView {
    /// Tags the purchase with the Munin user ID, so Munin can match it to this account.
    func purchaseOptions(_ product: Product) async -> Set<Product.PurchaseOption> {
        guard let token = subscriptions.appAccountToken(auth: auth) else { return [] }
        return [.appAccountToken(token)]
    }

    /// Sends a completed purchase to Munin, and closes the paywall once Munin
    /// confirms it. If Munin can't, the error shows in the header.
    func purchaseCompleted(_ product: Product, _ result: Result<Product.PurchaseResult, any Error>) async {
        await subscriptions.handlePurchase(result, auth: auth)
        if subscriptions.status?.active == true { dismiss() }
    }
}

/// The paywall's marketing header: app name, what the subscription gives,
/// a payment problem with Manage Subscription, and why the last purchase or
/// restore couldn't be linked.
private struct PaywallHeader: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.openURL) private var openURL
    /// iOS: shows the App Store's Manage Subscriptions sheet.
    @State private var isManagingSubscription = false

    var body: some View {
        VStack(spacing: DesignKit.Spacing.Primitive.s12) {
            Image(DesignKit.Asset.appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 128)
            Text("subscription.title")
                .font(.largeTitle.bold())
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
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        #endif
    }

    /// Opens subscription management, to update the payment method.
    private func manageSubscription() {
        #if os(iOS)
        isManagingSubscription = true
        #else
        openURL(AppLinks.manageSubscriptions)
        #endif
    }
}
