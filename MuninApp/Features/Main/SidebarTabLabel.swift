import SwiftUI

/// A tab's label in the sidebar or tab bar.
///
/// On macOS, the symbol is drawn into an image in the app's accent color, so
/// the sidebar shows it in that color rather than the system accent.
struct SidebarTabLabel: View {
    /// The tab's name.
    let title: LocalizedStringKey
    /// The SF Symbol name of the tab's icon.
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
