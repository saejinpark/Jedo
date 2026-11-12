import CoreGraphics
import Foundation

/// Notices when a stroke turns back on itself, as an eraser rubbed back and
/// forth does, and marks a new pass there so each rub takes off a little more.
struct RubTracker: Sendable {
    /// How far a run must go before its direction counts.
    let minRun: Double
    /// How far back the stroke must come for a new pass to begin.
    let turnBack: Double

    private var anchor: CGPoint?
    private var direction: (x: Double, y: Double)?
    private var furthest = 0.0
    private(set) var passes = 1

    init(pixelsPerMillimeter ppmm: Double, minRunMM: Double = 1.5, turnBackMM: Double = 1.5) {
        minRun = minRunMM * ppmm
        turnBack = turnBackMM * ppmm
    }

    mutating func track(_ sample: StrokeSample) -> StrokeSample {
        var out = sample
        out.beginsPass = false
        let p = sample.location
        guard let start = anchor else {
            anchor = p
            return out
        }
        let dx = Double(p.x - start.x), dy = Double(p.y - start.y)
        guard let dir = direction else {
            let run = hypot(dx, dy)
            if run >= minRun {
                direction = (dx / run, dy / run)
                furthest = run
            }
            return out
        }
        let along = dx * dir.x + dy * dir.y
        furthest = max(furthest, along)
        if furthest - along >= turnBack {
            // Coming back over what it just rubbed.
            anchor = p
            direction = nil
            furthest = 0
            passes += 1
            out.beginsPass = true
        }
        return out
    }
}
