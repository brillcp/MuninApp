import SwiftUI

/// Shown at the bottom of the Vault while Munin isn't turned on for AutoFill:
/// Set Up opens the guide, the close button hides the banner for good.
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
    /// Opens the setup guide.
    func showGuide() {
        autoFill.isGuidePresented = true
    }

    /// Hides the banner; the guide stays in Settings.
    func dismissBanner() {
        autoFill.isBannerDismissed = true
    }
}
