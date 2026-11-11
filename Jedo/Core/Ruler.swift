import CoreGraphics
import Foundation

/// Where the ruler lies on the paper: its centre and the direction of its long side.
/// Canvas pixels and radians.
struct RulerPose: Equatable, Sendable {
    var center: CGPoint
    var angle: Double
}

/// A straight ruler lying on the paper. All lengths are canvas pixels.
///
/// In the ruler's own frame, `u` runs along its length from the centre and
/// `v` runs across it; the upper edge (with the graduations) is at
/// `v = -width/2` and the lower edge at `v = +width/2`.
struct Ruler: Equatable, Sendable {
    enum Edge: Equatable, Sendable { case upper, lower }

    var pose: RulerPose
    var length: Double
    var width: Double

    /// A 20 cm drafting ruler, 3 cm wide, with 5 mm spare at each end of the scale.
    static let lengthMM = 210.0
    static let widthMM = 30.0

    init(pose: RulerPose, length: Double, width: Double) {
        self.pose = pose
        self.length = length
        self.width = width
    }

    init(pose: RulerPose, pixelsPerMillimeter ppmm: Double) {
        self.init(pose: pose, length: Self.lengthMM * ppmm, width: Self.widthMM * ppmm)
    }

    private var axis: (x: Double, y: Double) { (cos(pose.angle), sin(pose.angle)) }
    private var normal: (x: Double, y: Double) { (-sin(pose.angle), cos(pose.angle)) }

    /// A point in the ruler's frame.
    func local(_ p: CGPoint) -> (u: Double, v: Double) {
        let dx = Double(p.x - pose.center.x), dy = Double(p.y - pose.center.y)
        return (dx * axis.x + dy * axis.y, dx * normal.x + dy * normal.y)
    }

    /// A point given in the ruler's frame, back on the paper.
    func point(u: Double, v: Double) -> CGPoint {
        CGPoint(x: Double(pose.center.x) + axis.x * u + normal.x * v,
                y: Double(pose.center.y) + axis.y * u + normal.y * v)
    }

    /// Whether `u` lies alongside the ruler, between its ends.
    func spans(u: Double) -> Bool { abs(u) <= length / 2 }

    func contains(_ p: CGPoint, margin: Double = 0) -> Bool {
        let (u, v) = local(p)
        return abs(u) <= length / 2 + margin && abs(v) <= width / 2 + margin
    }

    /// How far `v` is outside an edge; negative means under the ruler.
    func outsideDistance(v: Double, from edge: Edge) -> Double {
        switch edge {
        case .upper: -width / 2 - v
        case .lower: v - width / 2
        }
    }

    /// The point `offset` pixels outside `edge`, level with `u`.
    func pointAlong(_ edge: Edge, u: Double, offset: Double) -> CGPoint {
        point(u: u, v: edge == .upper ? -width / 2 - offset : width / 2 + offset)
    }

    /// The side of the ruler's centre line that `v` is on.
    static func side(ofV v: Double) -> Edge { v < 0 ? .upper : .lower }
}

/// How fingers move a rigid object: no stretching, only sliding and turning.
enum RigidMotion {
    /// One finger slides the ruler.
    static func slide(_ pose: RulerPose, from old: CGPoint, to new: CGPoint) -> RulerPose {
        RulerPose(center: CGPoint(x: pose.center.x + new.x - old.x, y: pose.center.y + new.y - old.y),
                  angle: pose.angle)
    }

    /// Two fingers slide and turn it, as if both were pinned to it.
    /// The turn follows the line between the fingers; the slide follows their midpoint.
    static func slideAndTurn(_ pose: RulerPose, from old: (CGPoint, CGPoint), to new: (CGPoint, CGPoint)) -> RulerPose {
        let oldVector = (x: Double(old.1.x - old.0.x), y: Double(old.1.y - old.0.y))
        let newVector = (x: Double(new.1.x - new.0.x), y: Double(new.1.y - new.0.y))
        let oldMid = CGPoint(x: (old.0.x + old.1.x) / 2, y: (old.0.y + old.1.y) / 2)
        let newMid = CGPoint(x: (new.0.x + new.1.x) / 2, y: (new.0.y + new.1.y) / 2)

        // Fingers almost on top of each other give no reliable direction.
        guard hypot(oldVector.x, oldVector.y) > 4, hypot(newVector.x, newVector.y) > 4 else {
            return slide(pose, from: oldMid, to: newMid)
        }
        var turn = atan2(newVector.y, newVector.x) - atan2(oldVector.y, oldVector.x)
        if turn > .pi { turn -= 2 * .pi }
        if turn < -.pi { turn += 2 * .pi }

        let dx = Double(pose.center.x - oldMid.x), dy = Double(pose.center.y - oldMid.y)
        let c = cos(turn), s = sin(turn)
        return RulerPose(center: CGPoint(x: Double(newMid.x) + dx * c - dy * s,
                                         y: Double(newMid.y) + dx * s + dy * c),
                         angle: pose.angle + turn)
    }
}
