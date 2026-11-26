import SwiftUI

/// A view that shows a website's icon, or a globe placeholder until the icon loads.
///
/// Icons come from ``WebsiteIconStore``, which decodes them off the main
/// thread and caches them in memory only.
struct WebsiteIcon: View {
    /// The screen's scale, which decides how many pixels the icon is decoded at.
    @Environment(\.displayScale) private var displayScale
    /// The loaded icon, or `nil` while loading or if none is available.
    @State private var image: Image?

    /// The website's URL string.
    let url: String
    /// The icon's width and height in points.
    var size: CGFloat = DesignKit.Spacing.Primitive.s44

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                Image(systemName: DesignKit.Icon.website)
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: DesignKit.Spacing.Primitive.s12))
        .task(id: url, loadIcon)
    }
}

private extension WebsiteIcon {
    /// Loads the icon, already decoded at the size it's drawn, and fades it in.
    func loadIcon() async {
        let maxPixelSize = Int((size * displayScale).rounded(.up))
        let icon = await WebsiteIconStore.shared.image(for: url, maxPixelSize: maxPixelSize)
        let loaded = icon.map { Image(decorative: $0.cgImage, scale: displayScale) }
        withAnimation(DesignKit.Motion.easeInOut) { image = loaded }
    }
}
