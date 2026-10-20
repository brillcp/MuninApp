#if os(macOS)
import AppKit

/// Makes AppKit use Munin's accent instead of the user's system accent.
///
/// The sidebar's selection and icons ignore `.tint()` and the AccentColor asset
/// (unless the system accent is Multicolor), and draw with
/// `NSColor.controlAccentColor` / `selectedContentBackgroundColor`. This swaps
/// both class getters once at launch, the same way `TableSelectionStyle` does.
/// Parts AppKit renders internally may still use the system colour.
@MainActor
enum AccentColorOverride {
    private static var applied = false
    /// Read by AppKit from any thread; only written once, at launch.
    nonisolated(unsafe) fileprivate static var color = NSColor(resource: .accent)

    static func apply(color: NSColor) {
        self.color = color
        guard !applied else { return }
        applied = true
        swap(#selector(getter: NSColor.controlAccentColor), with: #selector(NSColor.munin_controlAccentColor))
        swap(#selector(getter: NSColor.selectedContentBackgroundColor), with: #selector(NSColor.munin_selectedContentBackgroundColor))
    }

    private static func swap(_ original: Selector, with replacement: Selector) {
        guard let originalMethod = class_getClassMethod(NSColor.self, original),
              let replacementMethod = class_getClassMethod(NSColor.self, replacement)
        else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

nonisolated private extension NSColor {
    @objc class func munin_controlAccentColor() -> NSColor {
        AccentColorOverride.color
    }

    @objc class func munin_selectedContentBackgroundColor() -> NSColor {
        AccentColorOverride.color
    }
}
#endif
