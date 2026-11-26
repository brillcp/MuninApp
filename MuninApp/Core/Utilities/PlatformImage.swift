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
