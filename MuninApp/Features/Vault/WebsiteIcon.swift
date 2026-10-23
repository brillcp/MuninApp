import SwiftUI

/// The item's website icon (apple-touch-icon or favicon), or a globe until one loads.
///
/// Icons come from `WebsiteIconStore`, which keeps them in memory only.
struct WebsiteIcon: View {
    /// The loaded icon.
    @State private var image: Image?

    /// The item's website.
    let url: String
    /// The icon's width and height in points.
    var size: CGFloat = 42.0

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: DesignKit.Spacing.Primitive.s12))
        .task(id: url) {
            let data = await WebsiteIconStore.shared.icon(for: url)
            image = data.flatMap(PlatformImage.init(data:)).map(Image.init(platformImage:))
        }
    }
}
