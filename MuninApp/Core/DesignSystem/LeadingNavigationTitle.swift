#if os(iOS)
import SwiftUI

extension View {
    /// Shows a localized title as plain text in the navigation bar's top-left
    /// corner, where it stays when the content scrolls, unlike the system's
    /// title, which moves to the middle.
    ///
    /// It's still the screen's navigation title, hidden from the bar, so the
    /// next screen's back button shows it. A `subtitle`, such as an item
    /// count, goes below it in a smaller, secondary font.
    ///
    /// - Parameters:
    ///   - titleKey: The title's localization key.
    ///   - subtitle: Text below the title, if any.
    ///   - showsLockButton: Whether a Lock button sits to the left of the title.
    ///   - onCancel: The action of a Cancel button (an xmark) to the left of
    ///     the title, for sheets, or `nil` for none.
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
    /// The action of a Cancel button to the left of the title, if any.
    let onCancel: (() -> Void)?

    func body(content: Content) -> some View {
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
                    MaximumWidth(DesignKit.Size.navigationTitleMaximumWidth) {
                        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s0) {
                            title
                                .font(.title3.weight(.semibold))
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
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}

/// Sizes its content to its natural width, but no wider than `maximum`, where
/// its text truncates.
///
/// A toolbar item isn't offered a width, so the title would take its full
/// width, and a long one would be moved into the bar's overflow menu instead
/// of shortened.
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
