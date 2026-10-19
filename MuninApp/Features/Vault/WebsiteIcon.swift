import SwiftUI

/// The item's website icon (apple-touch-icon or favicon), or a globe until one loads.
struct WebsiteIcon: View {
    let url: String
    var size: CGFloat = 38

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        #if os(iOS)
        .clipShape(.circle)
        #else
        .clipShape(.rect(cornerRadius: 12.0))
        #endif
        .task(id: url) {
            let data = await WebsiteIconStore.shared.icon(for: url)
            image = data.flatMap(PlatformImage.init(data:)).map(Image.init(platformImage:))
        }
    }
}
