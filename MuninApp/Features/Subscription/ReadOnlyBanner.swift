import SwiftUI

/// A banner that explains why the vault is read-only, with a button that opens
/// the paywall.
struct ReadOnlyBanner: View {
    @Environment(SubscriptionManager.self) private var subscriptions

    var body: some View {
        Banner {
            Label("subscription.readOnly", systemImage: DesignKit.Icon.locked)
        } actions: {
            Button("subscription.subscribe", action: showPaywall)
                .buttonStyle(.glassProminent)
        }
    }
}

private extension ReadOnlyBanner {
    /// Opens the paywall.
    func showPaywall() {
        subscriptions.isPaywallPresented = true
    }
}
