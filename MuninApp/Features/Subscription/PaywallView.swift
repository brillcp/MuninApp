import StoreKit
import SwiftUI

/// A view that offers the monthly subscription using the system subscription store.
///
/// The paywall appears after setup and on unlock while the vault is read-only.
/// Dismissing it leaves the vault read-only. Purchases are tagged with the
/// user's identifier as their app account token and sent to the server for
/// verification. The view dismisses itself once the server confirms the subscription.
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
    /// Returns purchase options that tag the purchase with the user's identifier, so the server can match it to the account.
    func purchaseOptions(_ product: Product) async -> Set<Product.PurchaseOption> {
        guard let token = subscriptions.appAccountToken(auth: auth) else { return [] }
        return [.appAccountToken(token)]
    }

    /// Sends a completed purchase to the server and dismisses the paywall once it's confirmed.
    ///
    /// If confirmation fails, the header shows the error.
    func purchaseCompleted(_ product: Product, _ result: Result<Product.PurchaseResult, any Error>) async {
        await subscriptions.handlePurchase(result, auth: auth)
        if subscriptions.status?.active == true { dismiss() }
    }
}

/// A view that shows the paywall's header.
///
/// The header describes the subscription and, when relevant, shows a billing
/// issue with a button to manage the subscription, or the error from the last
/// purchase or restore.
private struct PaywallHeader: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    /// A Boolean value that indicates whether the system's Manage Subscriptions sheet is presented on iOS.
    @State private var isManagingSubscription = false

    var body: some View {
        VStack(spacing: DesignKit.Spacing.Primitive.s12) {
            Image(colorScheme == .light ? DesignKit.Asset.appIcon : DesignKit.Asset.appIconDark)
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
}

private extension PaywallHeader {
    /// Opens subscription management so the user can update their payment method.
    func manageSubscription() {
        #if os(iOS)
        isManagingSubscription = true
        #else
        openURL(AppLinks.manageSubscriptions)
        #endif
    }
}
