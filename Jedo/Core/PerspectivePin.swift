import CoreGraphics
import Foundation

/// A pin pushed into the board at a vanishing point, and a straight edge
/// laid against it: the tool turns about the pin and slides along it, its
/// edge always running through the vanishing point, so every line drawn
/// along it heads there.
///
/// All points are paper pixels. One finger on a tool resting against a
/// pin swings it about the pin (the finger's turn about the pin) and slides
/// it along its edge (the finger's reach toward or away from the pin).
/// Slide it past its end and it comes off the pin.
enum PinPivot {
    /// Radius of the pin's shaft, which the edge rests against.
    static let shaftMM = 0.6
    /// How close an edge comes to the pin before it takes to it.
    static let catchMM = 1.5
    /// How far a pin may poke into a tool's body (a quick drag) and still be taken as touching.
    static let overlapMM = 6.0
    /// Straight sides shorter than this are corners, not edges to rest on.
    static let shortestSideMM = 8.0
    /// Within this of the pin, a finger's turn about it is too jumpy to follow.
    static let steadyReachMM = 12.0

    struct Side {
        var a: CGPoint
        var b: CGPoint
        /// Unit vector from a to b.
        var dir: (x: Double, y: Double)
        /// Unit vector pointing out of the body.
        var normal: (x: Double, y: Double)
        var length: Double

        /// How far `p` lies out from the side (negative inside) and how far along it.
        func measure(_ p: CGPoint) -> (out: Double, along: Double) {
            let rx = Double(p.x - a.x), ry = Double(p.y - a.y)
            return (rx * normal.x + ry * normal.y, rx * dir.x + ry * dir.y)
        }
    }

    /// Side `i` of a tool's outline, on the paper.
    static func side(_ shape: ToolShape, _ i: Int) -> Side {
        let points = shape.outline.map(shape.world)
        let a = points[i], b = points[(i + 1) % points.count]
        let ex = Double(b.x - a.x), ey = Double(b.y - a.y)
        let length = max(hypot(ex, ey), 1e-9)
        let dir = (x: ex / length, y: ey / length)
        let cx = points.reduce(0) { $0 + Double($1.x) } / Double(points.count)
        let cy = points.reduce(0) { $0 + Double($1.y) } / Double(points.count)
        var normal = (x: dir.y, y: -dir.x)
        if normal.x * (cx - Double(a.x)) + normal.y * (cy - Double(a.y)) > 0 { normal = (-normal.x, -normal.y) }
        return Side(a: a, b: b, dir: dir, normal: normal, length: length)
    }

    /// The straight sides of a tool long enough to lay against a pin.
    static func edges(_ shape: ToolShape, pixelsPerMillimeter ppmm: Double) -> [Int] {
        guard !shape.smooth else { return [] }
        return shape.outline.indices.filter { side(shape, $0).length >= shortestSideMM * ppmm }
    }

    /// The side a pin rests against, if one does. `before`, the tool as it
    /// lay a moment ago, tells which side the pin came from when a quick
    /// drag has carried the pin a little into the body.
    static func contact(_ shape: ToolShape, pin: CGPoint, before: ToolShape? = nil,
                        pixelsPerMillimeter ppmm: Double) -> Int? {
        let catchDistance = (shaftMM + catchMM) * ppmm, overlap = overlapMM * ppmm
        var best: (side: Int, score: Double)?
        for i in edges(shape, pixelsPerMillimeter: ppmm) {
            let s = side(shape, i)
            let (out, along) = s.measure(pin)
            guard along >= 0, along <= s.length, out <= catchDistance, out >= -overlap else { continue }
            // Inside the body it must have come from outside this side.
            if out < 0 {
                guard let before else { continue }
                let (wasOut, _) = side(before, i).measure(pin)
                guard wasOut >= 0 else { continue }
            }
            let score = abs(out)
            if best == nil || score < best!.score { best = (i, score) }
        }
        return best?.side
    }

    /// Moves the tool square to the pin, so side `i` just touches its shaft.
    static func settle(_ pose: ToolPose, side i: Int, pin: CGPoint, shapeAt: (ToolPose) -> ToolShape,
                       pixelsPerMillimeter ppmm: Double) -> ToolPose {
        let s = side(shapeAt(pose), i)
        let shift = s.measure(pin).out - shaftMM * ppmm
        var settled = pose
        settled.center.x += s.normal.x * shift
        settled.center.y += s.normal.y * shift
        return settled
    }

    /// A finger moving from `old` to `new` swings the tool about the pin and
    /// slides it along its edge. Returns nil once the edge slides off the pin.
    static func pivot(_ pose: ToolPose, side i: Int, pin: CGPoint, from old: CGPoint, to new: CGPoint,
                      shapeAt: (ToolPose) -> ToolShape, pixelsPerMillimeter ppmm: Double) -> ToolPose? {
        let ox = Double(old.x - pin.x), oy = Double(old.y - pin.y)
        let nx = Double(new.x - pin.x), ny = Double(new.y - pin.y)
        let oldReach = hypot(ox, oy), newReach = hypot(nx, ny)
        var moved = pose

        // Swing: the finger's turn about the pin, if it is far enough out to read.
        if oldReach > steadyReachMM * ppmm, newReach > steadyReachMM * ppmm {
            let turn = atan2(ny, nx) - atan2(oy, ox)
            let c = cos(turn), s = sin(turn)
            let dx = Double(pose.center.x - pin.x), dy = Double(pose.center.y - pin.y)
            moved.center = CGPoint(x: Double(pin.x) + dx * c - dy * s, y: Double(pin.y) + dx * s + dy * c)
            moved.angle = pose.angle + turn
        }

        // Slide: along the edge, as far as the finger moved along it.
        let s = side(shapeAt(moved), i)
        let along = Double(new.x - old.x) * s.dir.x + Double(new.y - old.y) * s.dir.y
        moved.center.x += s.dir.x * along
        moved.center.y += s.dir.y * along

        moved = settle(moved, side: i, pin: pin, shapeAt: shapeAt, pixelsPerMillimeter: ppmm)
        let onPin = side(shapeAt(moved), i).measure(pin).along
        guard onPin >= 0, onPin <= side(shapeAt(moved), i).length else { return nil }
        return moved
    }
}
