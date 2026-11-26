#if os(macOS)
import AppKit

/// Draws the selected row of every table in the app in a custom color on
/// macOS, such as the password list's selection.
///
/// It replaces `NSTableRowView.drawSelection(in:)` once at launch.
@MainActor
enum TableSelectionStyle {
    /// A Boolean value that indicates whether the method has been swizzled.
    ///
    /// Swizzling again would restore the original implementation.
    private static var applied = false
    /// The color that fills selected rows, at 40% opacity.
    private(set) static var selectionColor = NSColor(resource: .wood)

    /// Sets the color every table row uses to draw its selection.
    ///
    /// Call this method at launch. Later calls only update the color.
    ///
    /// - Parameter color: The selection color.
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
    /// The replacement for `drawSelection(in:)`, installed by
    /// ``TableSelectionStyle``.
    ///
    /// Fills the row with the selection color while the table is focused, and
    /// with a neutral gray otherwise.
    @objc func muninDrawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let color = TableSelectionStyle.selectionColor.withAlphaComponent(0.4)
        (isEmphasized ? color : .tertiaryLabelColor).setFill()
        bounds.fill()
    }
}
#endif
