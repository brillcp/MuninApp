import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A thin ring with a short arc spinning round it, in the accent color: the
/// app's loading indicator, used instead of `ProgressView`.
///
/// The arc spins clockwise on both platforms.
struct AccentSpinner: View {
    /// The app's accent color, from its asset catalog.
    ///
    /// The AutoFill extension has no asset catalog, so it passes its color explicitly.
    static let accentColor = Color("AccentColor")

    /// The ring's diameter.
    private let size: CGFloat
    /// The spinning arc's color.
    private let color: Color

    /// Creates the spinner.
    ///
    /// - Parameters:
    ///   - size: The ring's diameter.
    ///   - color: The spinning arc's color; the accent color unless the
    ///     background needs another, such as on an accent-colored button.
    init(size: CGFloat, color: Color = accentColor) {
        self.size = size
        self.color = color
    }

    var body: some View {
        SpinnerRepresentable(color: color, size: size)
            .frame(width: size, height: size)
    }
}

// MARK: - Private
private extension AccentSpinner {
    #if os(iOS)
    /// Hosts the spinner's backing view in SwiftUI on iOS.
    struct SpinnerRepresentable: UIViewRepresentable {
        /// The spinning arc's color.
        let color: Color
        /// The ring's diameter.
        let size: CGFloat

        func makeUIView(context: Context) -> SpinnerBackingView {
            SpinnerBackingView()
        }

        func updateUIView(_ uiView: SpinnerBackingView, context: Context) {
            uiView.update(color: color, size: size)
        }
    }

    /// A view that draws the ring and the spinning arc in its layers.
    final class SpinnerBackingView: UIView {
        /// The ring and the arc.
        private let layers = SpinnerLayers()
        /// The arc's color.
        private var color: UIColor = .tintColor

        override init(frame: CGRect) {
            super.init(frame: frame)
            layers.install(in: layer)
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
                view.applyColors()
            }
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            layers.install(in: layer)
        }

        /// Starts the spin again when the view comes back on screen, in case
        /// it was removed meanwhile.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            layers.addSpinIfNeeded(clockwiseRotation: 2 * .pi)
        }

        /// Applies a new color and size.
        func update(color: Color, size: CGFloat) {
            self.color = UIColor(color)
            layers.layout(size: size)
            applyColors()
        }

        /// Resolves the colors for light or dark mode.
        private func applyColors() {
            layers.setColors(
                track: UIColor.tertiaryLabel.resolvedColor(with: traitCollection).cgColor,
                arc: color.resolvedColor(with: traitCollection).cgColor
            )
        }
    }
    #else
    /// Hosts the spinner's backing view in SwiftUI on macOS.
    struct SpinnerRepresentable: NSViewRepresentable {
        /// The spinning arc's color.
        let color: Color
        /// The ring's diameter.
        let size: CGFloat

        func makeNSView(context: Context) -> SpinnerBackingView {
            SpinnerBackingView()
        }

        func updateNSView(_ nsView: SpinnerBackingView, context: Context) {
            nsView.update(color: color, size: size)
        }
    }

    /// A view that draws the ring and the spinning arc in its layers.
    final class SpinnerBackingView: NSView {
        /// The ring and the arc.
        private let layers = SpinnerLayers()
        /// The arc's color.
        private var color: NSColor = .controlAccentColor

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            if let layer { layers.install(in: layer) }
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
            if let layer { layers.install(in: layer) }
        }

        /// Starts the spin again when the view comes back on screen, in case
        /// it was removed meanwhile.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            layers.addSpinIfNeeded(clockwiseRotation: -2 * .pi)
        }

        /// Updates the colors when the appearance changes between light and dark.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applyColors()
        }

        /// Applies a new color and size.
        func update(color: Color, size: CGFloat) {
            self.color = NSColor(color)
            layers.layout(size: size)
            applyColors()
        }

        /// Resolves the colors for light or dark mode.
        private func applyColors() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layers.setColors(track: NSColor.tertiaryLabelColor.cgColor, arc: color.cgColor)
            }
        }
    }
    #endif

    /// The ring and the spinning arc, shared by both platforms' backing views.
    final class SpinnerLayers {
        /// The key of the spin animation on ``arc``.
        private static let spinKey = "spin"

        /// The full, faint ring.
        private let track = CAShapeLayer()
        /// The short arc that spins round the ring.
        private let arc = CAShapeLayer()

        /// Adds the ring and the arc to a view's layer.
        func install(in layer: CALayer) {
            for shape in [track, arc] {
                shape.fillColor = nil
                layer.addSublayer(shape)
            }
            arc.lineCap = .round
            arc.strokeEnd = 0.2
        }

        /// Sizes the ring and the arc to a diameter.
        func layout(size: CGFloat) {
            let lineWidth = max(2, size * 0.12)
            let bounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            let path = CGPath(ellipseIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), transform: nil)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for shape in [track, arc] {
                shape.frame = bounds
                shape.path = path
                shape.lineWidth = lineWidth
            }
            CATransaction.commit()
        }

        /// Sets the ring's and the arc's colors without animating.
        func setColors(track trackColor: CGColor, arc arcColor: CGColor) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            track.strokeColor = trackColor
            arc.strokeColor = arcColor
            CATransaction.commit()
        }

        /// Starts the spin unless it's already running.
        ///
        /// - Parameter clockwiseRotation: One full clockwise turn on the
        ///   platform: `2π` on iOS, `-2π` on macOS.
        func addSpinIfNeeded(clockwiseRotation: Double) {
            guard arc.animation(forKey: Self.spinKey) == nil else { return }
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = clockwiseRotation
            animation.duration = DesignKit.Motion.spinDuration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            arc.add(animation, forKey: Self.spinKey)
        }
    }
}
