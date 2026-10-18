#if os(macOS)
import AppKit

/// Applies a custom color as the table row selection highlight.
///
/// SwiftUI's `Table` ignores `.tint()` for selection on macOS, always using the
/// system accent color. This swizzles `NSTableRowView.drawSelection(in:)` once at
/// app launch so every table row in the app draws the custom color. Same as Oden.
@MainActor
enum TableSelectionStyle {
    private static var applied = false
    private(set) static var selectionColor = NSColor(resource: .wood)

    static func apply(color: NSColor) {
        selectionColor = color
        guard !applied else { return }
        applied = true

        guard let original = class_getInstanceMethod(NSTableRowView.self, #selector(NSTableRowView.drawSelection(in:))),
              let custom = class_getInstanceMethod(NSTableRowView.self, #selector(NSTableRowView.muninDrawSelection(in:)))
        else { return }
        method_exchangeImplementations(original, custom)
    }
}

private extension NSTableRowView {
    @objc func muninDrawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let color = TableSelectionStyle.selectionColor.withAlphaComponent(0.4)
        (isEmphasized ? color : .tertiaryLabelColor).setFill()
        bounds.fill()
    }
}
#endif
