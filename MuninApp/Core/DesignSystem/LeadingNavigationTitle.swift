import SwiftUI

extension View {
    /// Shows a screen's title, an optional subtitle, and optional Lock and
    /// Cancel buttons.
    ///
    /// On iOS, the title is plain text in the navigation bar's top-left
    /// corner, where it stays when the content scrolls. It's still the
    /// screen's navigation title, hidden from the bar, so the next screen's
    /// back button shows it. A `subtitle`, such as an item count, goes below
    /// it in a smaller, secondary font.
    ///
    /// On macOS, the title shows in the window's toolbar, with Lock at its
    /// leading edge and Cancel as the sheet's cancel button. With a
    /// `subtitle`, both are drawn by this modifier, so the subtitle's numbers
    /// roll when they change, as on iOS.
    ///
    /// - Parameters:
    ///   - titleKey: The title's localization key.
    ///   - subtitle: Text below the title, if any.
    ///   - showsLockButton: Whether a Lock button sits to the left of the title.
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
    /// The title, which is also the navigation title for the back button.
    let title: Text
    /// Text below the title, if any.
    let subtitle: Text?
    /// A Boolean value that indicates whether a Lock button sits to the left of the title.
    let showsLockButton: Bool
    /// The action of a Cancel button, if any.
    let onCancel: (() -> Void)?

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                if showsLockButton {
                    ToolbarItem(placement: .topBarLeading) { LockToolbarButton() }
                }
                if let onCancel {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .cancel, action: onCancel)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    MaximumWidth(DesignKit.Size.navigationTitleMaximumWidth) { titleStack }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        #else
        Group {
            if subtitle != nil {
                content
                    .navigationTitle(title)
                    .toolbar(removing: .title)
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
            if subtitle != nil {
                ToolbarItem(placement: .navigation) { titleStack }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
        #endif
    }

    /// The title, with the subtitle below it in a smaller, secondary font.
    ///
    /// The subtitle's numbers roll when they change, such as when the items load.
    private var titleStack: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s0) {
            title
                .font(titleFont)
            if let subtitle {
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .animation(DesignKit.Motion.quickBouncy, value: subtitle)
    }

    /// The title's font: larger on iOS, the toolbar's title size on macOS.
    private var titleFont: Font {
        #if os(iOS)
        .title3.weight(.semibold)
        #else
        .headline
        #endif
    }
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
