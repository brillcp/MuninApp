#if os(macOS)
import AppKit

/// Makes AppKit use the app's accent color instead of the system accent color.
///
/// The macOS sidebar selection ignores `.tint()` and the AccentColor asset
/// unless the system accent is Multicolor, and draws with
/// `NSColor.controlAccentColor` and `NSColor.selectedContentBackgroundColor`.
/// This type swizzles both class getters once at launch, as
/// ``TableSelectionStyle`` does for table selection. Elements that AppKit
/// renders internally may still use the system color.
@MainActor
enum AccentColorOverride {
    /// A Boolean value that indicates whether the getters are swizzled.
    ///
    /// Swizzling twice would restore the originals.
    private static var applied = false
    /// The color that the swizzled getters return.
    ///
    /// AppKit can read it from any thread; it's written only at launch.
    nonisolated(unsafe) fileprivate static var color = NSColor(named: "AccentColor") ?? .systemBlue

    /// Makes `controlAccentColor` and `selectedContentBackgroundColor` return
    /// the given color.
    ///
    /// Call this method at launch. Later calls only update the color.
    ///
    /// - Parameter color: The accent color to use.
    static func apply(color: NSColor) {
        self.color = color
        guard !applied else { return }
        applied = true
        swap(#selector(getter: NSColor.controlAccentColor), with: #selector(NSColor.munin_controlAccentColor))
        swap(#selector(getter: NSColor.selectedContentBackgroundColor), with: #selector(NSColor.munin_selectedContentBackgroundColor))
    }

    /// Exchanges the implementations of two `NSColor` class methods.
    private static func swap(_ original: Selector, with replacement: Selector) {
        guard let originalMethod = class_getClassMethod(NSColor.self, original),
              let replacementMethod = class_getClassMethod(NSColor.self, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

nonisolated private extension NSColor {
    /// The replacement for `controlAccentColor`, installed by ``AccentColorOverride``.
    @objc class func munin_controlAccentColor() -> NSColor {
        AccentColorOverride.color
    }

    /// The replacement for `selectedContentBackgroundColor`, installed by
    /// ``AccentColorOverride``.
    @objc class func munin_selectedContentBackgroundColor() -> NSColor {
        AccentColorOverride.color
    }
}
#endif
