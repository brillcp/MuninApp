import Foundation
import Observation

/// One clock for a screen of codes, ticking on whole seconds.
///
/// Rows get the clock itself and read `now` in their own body, so each row
/// updates itself. Passing the time as a `Date` didn't work in the Mac table:
/// it only redraws rows whose data changed, so the countdown froze.
@Observable
final class TwoFactorClock {
    /// The current time, updated on every whole second while `run()` is active.
    private(set) var now = Date.now

    /// Ticks until the calling task is cancelled (use from `.task`).
    func run() async {
        now = .now
        while !Task.isCancelled {
            let fraction = Date.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
            try? await Task.sleep(for: .seconds(1 - fraction))
            now = .now
        }
    }
}
