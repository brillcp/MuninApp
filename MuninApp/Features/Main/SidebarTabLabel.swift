import SwiftUI

/// A tab's label in the sidebar or tab bar.
///
/// The macOS sidebar tints SF Symbols with the system accent color and ignores
/// `tint`, `listItemTint`, and `foregroundStyle`. To use the app's accent, the
/// symbol is rendered into a non-template image in fixed colors, which the
/// sidebar can't recolor.
struct SidebarTabLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// A Boolean value that indicates whether the tab is selected, which turns the macOS icon white.
    let isSelected: Bool

    var body: some View {
        Label {
            Text(title)
        } icon: {
            #if os(macOS)
            if let image = coloredSymbol {
                Image(nsImage: image)
            } else {
                Image(systemName: systemImage)
            }
            #else
            Image(systemName: systemImage)
            #endif
        }
    }
}

#if os(macOS)
private extension SidebarTabLabel {
    /// The symbol rendered as a non-template image in the accent color, or
    /// white when selected; `nil` if the symbol doesn't exist.
    var coloredSymbol: NSImage? {
        let color = isSelected ? NSColor.white : NSColor(resource: .accent)
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }
}
#endif
