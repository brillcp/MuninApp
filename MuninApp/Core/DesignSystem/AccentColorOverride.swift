#if os(macOS)
import AppKit

/// Makes AppKit use Munin's accent colour instead of the user's system accent.
///
/// The Mac sidebar's selection ignores `.tint()` and the AccentColor asset
/// (unless the system accent is set to Multicolor), and draws with
/// `NSColor.controlAccentColor` and `NSColor.selectedContentBackgroundColor`.
/// This swaps both class getters once at launch, the same way
/// `TableSelectionStyle` swaps the table selection drawing. Parts that AppKit
/// renders internally may still use the system colour.
@MainActor
enum AccentColorOverride {
    /// Whether the getters have already been swapped. Swapping twice would undo it.
    private static var applied = false
    /// The colour the swapped getters return.
    ///
    /// AppKit can read it from any thread; it's only written at launch.
    nonisolated(unsafe) fileprivate static var color = NSColor(resource: .accent)

    /// Makes `controlAccentColor` and `selectedContentBackgroundColor` return
    /// `color`. Call once at launch; later calls only update the colour.
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
    /// Replacement for `controlAccentColor`, installed by `AccentColorOverride`.
    @objc class func munin_controlAccentColor() -> NSColor {
        AccentColorOverride.color
    }

    /// Replacement for `selectedContentBackgroundColor`, installed by `AccentColorOverride`.
    @objc class func munin_selectedContentBackgroundColor() -> NSColor {
        AccentColorOverride.color
    }
}
#endif
