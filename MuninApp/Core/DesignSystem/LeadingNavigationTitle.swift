import SwiftUI

extension View {
    /// Shows a screen's title, an optional subtitle, and optional Lock and
    /// Cancel buttons.
    ///
    /// On iOS, the title is plain text in the navigation bar's top-left
    /// corner, where it stays when the content scrolls. It's still the
    /// screen's navigation title, hidden from the bar, so the next screen's
    /// back button shows it. A `subtitle`, such as an item count, goes below
    /// it in a smaller, secondary font. When a camera sits where the bar's
    /// buttons are, as on a folded iPhone Duo, the bar uses its standard
    /// left-aligned title instead, so its buttons move clear of the camera,
    /// and Lock moves to the trailing side.
    ///
    /// On macOS, it's the window's standard title and subtitle, with Lock at
    /// the toolbar's leading edge and Cancel as the sheet's cancel button.
    ///
    /// - Parameters:
    ///   - titleKey: The title's localization key.
    ///   - subtitle: Text below the title, if any.
    ///   - showsLockButton: Whether the toolbar shows a Lock button.
    ///   - onCancel: The action of a Cancel button (an xmark), for sheets, or
    ///     `nil` for none.
    func leadingNavigationTitle(
        _ titleKey: LocalizedStringKey,
        subtitle: Text? = nil,
        showsLockButton: Bool = false,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        modifier(LeadingNavigationTitle(title: Text(titleKey), subtitle: subtitle, showsLockButton: showsLockButton, onCancel: onCancel))
    }
}

/// The modifier behind ``SwiftUI/View/leadingNavigationTitle(_:subtitle:showsLockButton:onCancel:)``.
private struct LeadingNavigationTitle: ViewModifier {
    /// A Boolean value that indicates whether the bar uses the standard title
    /// instead of the custom one, because a camera sits where the bar's
    /// buttons are, as on a folded iPhone Duo.
    @State private var usesStandardTitle = false

    /// The title, which is also the navigation title for the back button.
    let title: Text
    /// Text below the title, if any.
    let subtitle: Text?
    /// A Boolean value that indicates whether the toolbar shows a Lock button.
    let showsLockButton: Bool
    /// The action of a Cancel button, if any.
    let onCancel: (() -> Void)?

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - subtitle: Text below the title, if any.
    ///   - showsLockButton: Whether the toolbar shows a Lock button.
    ///   - onCancel: The action of a Cancel button, or `nil` for none.
    init(title: Text, subtitle: Text?, showsLockButton: Bool, onCancel: (() -> Void)?) {
        self.title = title
        self.subtitle = subtitle
        self.showsLockButton = showsLockButton
        self.onCancel = onCancel
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationTitle(title)
            .toolbarTitleDisplayMode(usesStandardTitle ? .inlineLarge : .inline)
            .toolbar(removing: usesStandardTitle ? nil : .title)
            .toolbar {
                if showsLockButton {
                    ToolbarItem(placement: usesStandardTitle ? .topBarTrailing : .topBarLeading) { LockToolbarButton() }
                }
                if let onCancel {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .cancel, action: onCancel)
                    }
                }
                if usesStandardTitle {
                    if let subtitle {
                        ToolbarItem(placement: .subtitle) { styled(subtitle) }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        MaximumWidth(DesignKit.Size.navigationTitleMaximumWidth) { titleStack }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: Bool.self, of: Self.hasCameraInBar) { usesStandardTitle = $0 }
            }
        #else
        Group {
            if let subtitle {
                content
                    .navigationTitle(title)
                    .navigationSubtitle(subtitle)
            } else {
                content
                    .navigationTitle(title)
            }
        }
        .toolbar {
            if showsLockButton {
                ToolbarItem(placement: .navigation) { LockToolbarButton() }
            }
            if let onCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel, action: onCancel)
                }
            }
        }
        #endif
    }

    #if os(iOS)
    /// The title, with the subtitle below it.
    private var titleStack: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s0) {
            title.font(.title3.weight(.semibold))
            if let subtitle {
                styled(subtitle)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// The subtitle in a smaller, secondary font, whose numbers roll when
    /// they change, such as when the items load.
    private func styled(_ subtitle: Text) -> some View {
        subtitle
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .animation(DesignKit.Motion.quickBouncy, value: subtitle)
    }

    /// Returns whether a camera sits in the top trailing corner, where the
    /// bar's buttons are, as on a folded iPhone Duo.
    ///
    /// The proxy covers the whole screen, including the bar. A camera in the
    /// middle of the top edge, like the Dynamic Island, doesn't count.
    private nonisolated static func hasCameraInBar(_ proxy: GeometryProxy) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        let size = proxy.size
        return proxy.reservedRegions(kind: .occlusion).contains { region in
            region.frame.midX > size.width * 0.6 && region.frame.midY < size.height * 0.2
        }
    }
    #endif
}

#if os(iOS)
/// Sizes its content to its natural width, but no wider than `maximum`, where
/// its text truncates, so a long title stays on one line in the bar.
private struct MaximumWidth: Layout {
    /// The widest the content can be.
    let maximum: CGFloat

    /// Creates the layout.
    ///
    /// - Parameter maximum: The widest the content can be.
    init(_ maximum: CGFloat) {
        self.maximum = maximum
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        return subview.sizeThatFits(cappedProposal(for: subview, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        subview.place(at: bounds.origin, proposal: cappedProposal(for: subview, height: proposal.height))
    }

    /// The content's natural width, capped at `maximum`.
    private func cappedProposal(for subview: LayoutSubview, height: CGFloat?) -> ProposedViewSize {
        let natural = subview.sizeThatFits(.unspecified).width
        return ProposedViewSize(width: min(natural, maximum), height: height)
    }
}
#endif
