import SwiftUI
#if os(iOS)
import UIKit
/// The platform's image type: `UIImage` on iOS.
typealias PlatformImage = UIImage
#else
import AppKit
/// The platform's image type: `NSImage` on macOS.
typealias PlatformImage = NSImage
#endif

extension Image {
    /// Creates an image from a platform image.
    ///
    /// - Parameter platformImage: A `UIImage` on iOS or an `NSImage` on macOS.
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}
