import SwiftUI

/// A banner that prompts the user to turn on AutoFill.
///
/// The vault shows the banner while AutoFill is off. Set Up opens the setup
/// guide, and the close button dismisses the banner permanently.
struct AutoFillBanner: View {
    @Environment(AutoFillSetup.self) private var autoFill

    var body: some View {
        Banner {
            Label("autofill.banner", systemImage: DesignKit.Icon.autoFill)
        } actions: {
            Button("autofill.banner.setUp", action: showGuide)
                .buttonStyle(.glassProminent)
            Button("global.close", systemImage: DesignKit.Icon.close, action: dismissBanner)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
    }
}

private extension AutoFillBanner {
    /// Opens the AutoFill setup guide.
    func showGuide() {
        autoFill.isGuidePresented = true
    }

    /// Dismisses the banner permanently. The guide remains available in Settings.
    func dismissBanner() {
        autoFill.isBannerDismissed = true
    }
}
