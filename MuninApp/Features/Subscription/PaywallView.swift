import StoreKit
import SwiftUI

/// A view that offers the monthly subscription using the system subscription store.
///
/// The paywall appears after setup and on unlock while the vault is read-only.
/// Dismissing it leaves the vault read-only. Purchases are tagged with the
/// user's identifier as their app account token and sent to the server for
/// verification. The view dismisses itself once the server confirms the subscription.
struct PaywallView: View {
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
    /// Returns purchase options that tag the purchase with the user's identifier, so the server can match it to the account.
    func purchaseOptions(_ product: Product) async -> Set<Product.PurchaseOption> {
        guard let token = subscriptions.appAccountToken() else { return [] }
        return [.appAccountToken(token)]
    }

    /// Sends a completed purchase to the server and dismisses the paywall once it's confirmed.
    ///
    /// If confirmation fails, the header shows the error.
    func purchaseCompleted(_ product: Product, _ result: Result<Product.PurchaseResult, any Error>) async {
        await subscriptions.handlePurchase(result)
        if subscriptions.status?.active == true { dismiss() }
    }
}
