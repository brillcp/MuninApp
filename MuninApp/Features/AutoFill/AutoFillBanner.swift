import SwiftUI

/// A banner that prompts the user to turn on AutoFill.
///
/// The vault shows the banner while AutoFill is off. Set Up opens the setup
/// guide, and the close button dismisses the banner permanently.
struct AutoFillBanner: View {
    @Environment(AutoFillSetup.self) private var autoFill

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            Label("autofill.banner", systemImage: DesignKit.Icon.autoFill)
                .font(.callout)
            Spacer()
            Button("autofill.banner.setUp", action: showGuide)
                .buttonStyle(.glassProminent)
            Button("global.close", systemImage: DesignKit.Icon.close, action: dismissBanner)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
        .padding(DesignKit.Spacing.Primitive.s12)
        .glassEffect(in: .rect(cornerRadius: DesignKit.Spacing.Primitive.s16))
        .padding(DesignKit.Spacing.Primitive.s12)
    }
}

private extension AutoFillBanner {
    func showGuide() {
        autoFill.isGuidePresented = true
    }

    /// Dismisses the banner permanently. The guide remains available in Settings.
    func dismissBanner() {
        autoFill.isBannerDismissed = true
    }
}
