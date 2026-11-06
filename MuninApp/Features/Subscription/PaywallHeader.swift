import StoreKit
import SwiftUI

/// A view that shows the paywall's header.
///
/// The header describes the subscription and, when relevant, shows a billing
/// issue with a button to manage the subscription, or the error from the last
/// purchase or restore.
struct PaywallHeader: View {
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
