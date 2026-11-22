import SwiftUI

/// A view that shows the read-only or billing issue banner at the bottom of a
/// list, or another banner when neither applies.
///
/// On macOS, the banners start after the sidebar.
struct SubscriptionBanners<Fallback: View>: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    /// The width the macOS sidebar covers, which the banners start after.
    @Environment(\.sidebarWidth) private var sidebarWidth

    /// The banner to show when the subscription needs no banner.
    @ViewBuilder let fallback: Fallback

    var body: some View {
        Group {
            if subscriptions.isReadOnly {
                ReadOnlyBanner()
            } else if subscriptions.isInGracePeriod {
                BillingIssueBanner()
            } else {
                fallback
            }
        }
        .padding(.leading, sidebarWidth)
    }
}

extension SubscriptionBanners where Fallback == EmptyView {
    /// Creates the subscription banners with nothing shown when neither applies.
    init() {
        fallback = EmptyView()
    }
}
