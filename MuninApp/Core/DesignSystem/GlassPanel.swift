import SwiftUI

extension View {
    /// Places the view on a rounded glass panel, like the password panel,
    /// the macOS sidebar, and the banners.
    func glassPanel() -> some View {
        glassEffect(in: .rect(cornerRadius: DesignKit.Spacing.Primitive.s16))
    }
}
