import Foundation
import Observation

/// An observable clock that ticks on whole seconds, shared by a screen of codes.
///
/// Pass the clock itself to each row and read ``now`` in the row's body, so
/// every row updates independently. The macOS table redraws only rows whose
/// data changed, so passing the time as a `Date` value would freeze the countdown.
@Observable
final class TwoFactorClock {
    /// The current time, updated on every whole second while ``run()`` is active.
    private(set) var now = Date.now
}

extension TwoFactorClock {
    /// Updates ``now`` every second until the calling task is cancelled.
    ///
    /// Call this from a `task` modifier.
    func run() async {
        now = .now
        while !Task.isCancelled {
            let fraction = Date.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
            try? await Task.sleep(for: .seconds(1 - fraction))
            now = .now
        }
    }
}
