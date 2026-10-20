#if os(macOS)
import AppKit

/// Applies a custom colour as the table row selection highlight.
///
/// SwiftUI's `Table` ignores `.tint()` for selection on macOS and always uses
/// the system accent colour. This swizzles `NSTableRowView.drawSelection(in:)`
/// once at app launch, so every table row in the app draws the custom colour.
@MainActor
enum TableSelectionStyle {
    /// Whether the method has already been swapped. Swapping twice would undo it.
    private static var applied = false
    /// The colour selected rows are filled with (at 40% opacity).
    private(set) static var selectionColor = NSColor(resource: .wood)

    /// Makes every table row draw its selection with `color`. Call once at
    /// launch; later calls only update the colour.
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
    /// Replacement for `drawSelection(in:)`, installed by `TableSelectionStyle`.
    ///
    /// Fills the row with the selection colour while the table is focused,
    /// and with a neutral grey while it isn't.
    @objc func muninDrawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let color = TableSelectionStyle.selectionColor.withAlphaComponent(0.4)
        (isEmphasized ? color : .tertiaryLabelColor).setFill()
        bounds.fill()
    }
}
#endif
