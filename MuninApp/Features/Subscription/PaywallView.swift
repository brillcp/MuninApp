import StoreKit
import SwiftUI

/// The subscription screen: Apple's subscription store for Munin's monthly
/// plan, with its free trial, price and Restore Purchases.
///
/// Shown after setup, and on unlock while the vault is read-only. Closing it
/// keeps the vault read-only. Purchases carry the user's ID as their app
/// account token and are sent to Munin to check with Apple.
struct PaywallView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SubscriptionManager.self) private var subscriptions

    var body: some View {
        SubscriptionStoreView(productIDs: [SubscriptionManager.productID]) {
            PaywallHeader()
        }
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
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

    /// Sends a completed purchase to Munin.
    func purchaseCompleted(_ product: Product, _ result: Result<Product.PurchaseResult, any Error>) async {
        await subscriptions.handlePurchase(result, auth: auth)
    }
}

/// The paywall's marketing header: app name and what the subscription gives.
private struct PaywallHeader: View {
    var body: some View {
        VStack(spacing: DesignKit.Spacing.Primitive.s12) {
            Image("icon-512")
                .resizable()
                .scaledToFit()
                .frame(width: 128)
            Text("subscription.title")
                .font(.largeTitle.bold())
            Text("subscription.message")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(DesignKit.Spacing.Primitive.s24)
    }
}
