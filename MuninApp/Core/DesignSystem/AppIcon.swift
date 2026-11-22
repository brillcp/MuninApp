import SwiftUI

/// A view that shows the app's icon, with rounded corners like the home
/// screen's and a thin border.
///
/// The corner radius is computed from the size, so the border follows the
/// corners at any size.
struct AppIcon: View {
    /// The home screen's corner radius as a share of the icon's size.
    private static let cornerRadiusRatio: CGFloat = 0.225

    @Environment(\.colorScheme) private var colorScheme

    /// The icon's width and height.
    let size: CGFloat

    var body: some View {
        Image(colorScheme == .light ? DesignKit.Asset.appIcon : DesignKit.Asset.appIconDark)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.quaternary, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private extension AppIcon {
    /// The icon's rounded shape, used to clip it and draw the border.
    var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * Self.cornerRadiusRatio, style: .continuous)
    }
}
