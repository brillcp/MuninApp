import SwiftUI

/// Munin's design tokens.
enum DesignKit {
    /// Spacing tokens, for paddings and stack spacing.
    enum Spacing {
        enum Primitive {
            static let s0: CGFloat = 0
            static let s2: CGFloat = 2
            static let s4: CGFloat = 4
            static let s6: CGFloat = 6
            static let s8: CGFloat = 8
            static let s12: CGFloat = 12
            static let s16: CGFloat = 16
            static let s24: CGFloat = 24
            static let s32: CGFloat = 32
            static let s40: CGFloat = 40
            static let s48: CGFloat = 48
            static let s56: CGFloat = 56
            static let s64: CGFloat = 64
            static let s72: CGFloat = 72
        }
    }

    /// Animation tokens, for implicit and explicit animations.
    enum Motion {
        /// The system default, for small state changes like copy feedback.
        static let linear: Animation = .linear(duration: 0.25)
        /// A springy bounce, for content that changes step or size.
        static let bouncy: Animation = .bouncy
        /// A short bounce, for showing and hiding panels.
        static let quickBouncy: Animation = .bouncy(duration: 0.25)
        /// A gentle ease, for color and tint changes.
        static let easeInOut: Animation = .easeInOut
        /// A slow, smooth curve, for full-screen transitions like the lock screen.
        static let slowSmooth: Animation = .smooth(duration: 0.45)
    }
}
