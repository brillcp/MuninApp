import SwiftUI

/// A banner that explains why the vault is read-only, with a button that opens
/// the paywall.
struct ReadOnlyBanner: View {
    @Environment(SubscriptionManager.self) private var subscriptions

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            Label("subscription.readOnly", systemImage: DesignKit.Icon.locked)
                .font(.callout)
            Spacer()
            Button("subscription.subscribe", action: showPaywall)
                .buttonStyle(.glassProminent)
        }
        .padding(DesignKit.Spacing.Primitive.s12)
        .glassEffect(in: .rect(cornerRadius: DesignKit.Spacing.Primitive.s16))
        .padding(DesignKit.Spacing.Primitive.s12)
    }
}

private extension ReadOnlyBanner {
    func showPaywall() {
        subscriptions.isPaywallPresented = true
    }
}
