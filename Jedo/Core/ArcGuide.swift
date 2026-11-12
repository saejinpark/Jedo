import CoreGraphics
import Foundation

/// Swings a stroke round the compass needle: wherever the pencil goes, the
/// lead stays on the circle, in the direction of the pencil from the needle.
///
/// It also notices when the lead goes back over its own line, turning back
/// or coming round a full lap, and marks a new pass there, so the line
/// darkens the way going over it with a real compass does.
///
/// A value type, so a copy can run ahead over predicted touches.
struct ArcGuide: Sendable {
    let center: CGPoint
    let radius: Double
    /// Closer than this to the needle the pencil's direction means nothing, so the lead waits.
    let deadZone: Double
    /// How far the lead must come back before it counts as going over the line again.
    let reverseDistance: Double
    /// Longest step between samples on the arc, short enough that the chord can't be seen.
    let maxStep: Double

    /// Direction of the lead from the needle, once it has touched down.
    private(set) var angle: Double?
    /// Passes over the paper so far in this stroke.
    private(set) var passes = 1

    private var last: StrokeSample?
    /// +1 or -1 once the lead has clearly set off one way round, 0 before.
    private var direction: Double = 0
    /// Signed arc length before the direction is clear.
    private var wander: Double = 0
    /// Arc length travelled in this pass, and the furthest it got.
    private var progress: Double = 0
    private var furthest: Double = 0

    /// A compass lead stands upright, whatever the pencil's tilt.
    static let leadAltitude = Double.pi / 2
    static let reverseMM = 1.5
    /// The chord between steps strays at most this many pixels from the true arc.
    static let chordTolerance = 0.05

    init(center: CGPoint, radius: Double, pixelsPerMillimeter ppmm: Double) {
        self.center = center
        self.radius = radius
        deadZone = radius * 0.3
        reverseDistance = Self.reverseMM * ppmm
        // Sagitta s²/8r stays below the tolerance.
        maxStep = max((8 * radius * Self.chordTolerance).squareRoot(), 0.5)
    }

    var lead: CGPoint? { angle.map(point(at:)) }

    /// The samples the lead lays down as the pencil reaches `sample`. Empty
    /// while the pencil is too close to the needle to say which way it points.
    mutating func guide(_ sample: StrokeSample) -> [StrokeSample] {
        let dx = Double(sample.location.x - center.x), dy = Double(sample.location.y - center.y)
        guard (dx * dx + dy * dy).squareRoot() >= max(deadZone, 1e-9) else { return [] }
        let target = atan2(dy, dx)

        var upright = sample
        upright.altitude = Self.leadAltitude
        upright.beginsPass = false

        guard let from = angle, let previous = last else {
            upright.location = point(at: target)
            angle = target
            last = upright
            return [upright]
        }

        let delta = Self.wrapped(target - from)
        let steps = max(Int((abs(delta) * radius / maxStep).rounded(.up)), 1)
        let stepLength = delta * radius / Double(steps)
        var out: [StrokeSample] = []
        out.reserveCapacity(steps)
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            var s = StrokeSample.interpolate(previous, upright, t)
            s.location = point(at: from + delta * t)
            s.beginsPass = track(stepLength)
            out.append(s)
        }
        angle = Self.wrapped(target)
        last = out.last
        return out
    }

    /// Follows the lead round and says whether this step starts a new pass.
    private mutating func track(_ step: Double) -> Bool {
        guard direction != 0 else {
            wander += step
            if abs(wander) >= reverseDistance {
                direction = wander > 0 ? 1 : -1
                progress = abs(wander)
                furthest = progress
            }
            return false
        }
        progress += step * direction
        furthest = max(furthest, progress)
        if furthest - progress >= reverseDistance {
            // Turned back: from here it goes over what it just drew.
            direction = -direction
            progress = furthest - progress
            furthest = progress
            passes += 1
            return true
        }
        let lap = 2 * Double.pi * radius
        if progress >= lap {
            progress -= lap
            furthest = progress
            passes += 1
            return true
        }
        return false
    }

    private func point(at angle: Double) -> CGPoint {
        CGPoint(x: Double(center.x) + cos(angle) * radius, y: Double(center.y) + sin(angle) * radius)
    }

    /// Into -π...π.
    static func wrapped(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }
}
