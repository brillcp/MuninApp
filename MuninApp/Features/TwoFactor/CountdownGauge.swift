import SwiftUI

/// A gauge that counts down to the next code.
///
/// The only part of a row that redraws every second. It turns red for the
/// last five seconds.
struct CountdownGauge: View, Equatable {
    /// The number of seconds until the code changes.
    let remaining: Int
    /// The code's period, in seconds.
    let period: Int

    var body: some View {
        Gauge(value: Double(remaining), in: 0...Double(max(period, 1))) {
            Text(remaining, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(remaining <= 5 ? Color.red : Color.green)
        .scaleEffect(0.6)
        .accessibilityLabel(LocalizedKey("codes.row.secondsLeft", remaining))
        .animation(DesignKit.Motion.quickBouncy, value: remaining)
    }
}
