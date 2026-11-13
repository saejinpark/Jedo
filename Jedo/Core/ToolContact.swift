import CoreGraphics
import Foundation

/// Rigid tools lying on the paper don't pass through each other: a set
/// square pushed against the ruler stops at its edge and slides along it,
/// the way it does on a real drawing board. Tools already overlapping when
/// one is picked up are stacked and pass over each other freely.
enum ToolContact {
    /// The flat, straight-sided plates that butt against each other. Curves
    /// stay free: their outlines are not simple convex plates.
    static func collides(_ kind: ToolKind) -> Bool {
        switch kind {
        case .ruler, .parallelRule, .setSquare45, .setSquare60, .protractor,
             .circleTemplate, .ellipseTemplate, .squareTemplate, .hexTemplate, .arcTemplate, .letteringGuide: true
        case .scaleRule: true
        // A sheet of steel thinner than paper: it slips under and over the others.
        case .frenchCurveA, .frenchCurveB, .frenchCurveC, .hipCurve, .erasingShield: false
        }
    }

    /// A shape's outline on the paper.
    static func polygon(_ shape: ToolShape) -> [CGPoint] { shape.outline.map(shape.world) }

    /// The shortest move that takes convex polygon `a` out of convex polygon
    /// `b`, or nil if they don't overlap.
    static func separation(_ a: [CGPoint], from b: [CGPoint]) -> CGVector? {
        var best: (axis: (x: Double, y: Double), depth: Double)?
        for polygon in [a, b] {
            for i in polygon.indices {
                let p = polygon[i], q = polygon[(i + 1) % polygon.count]
                let ex = Double(q.x - p.x), ey = Double(q.y - p.y)
                let length = hypot(ex, ey)
                guard length > 1e-9 else { continue }
                let axis = (x: -ey / length, y: ex / length)
                let (minA, maxA) = project(a, axis), (minB, maxB) = project(b, axis)
                let depth = min(maxA, maxB) - max(minA, minB)
                if depth <= 0 { return nil }
                if best == nil || depth < best!.depth { best = (axis, depth) }
            }
        }
        guard var (axis, depth) = best else { return nil }
        // Push `a` away from `b`.
        let ca = centre(a), cb = centre(b)
        if (Double(ca.x - cb.x)) * axis.x + (Double(ca.y - cb.y)) * axis.y < 0 { axis = (-axis.x, -axis.y) }
        depth += 1e-3
        return CGVector(dx: axis.x * depth, dy: axis.y * depth)
    }

    static func overlaps(_ a: [CGPoint], _ b: [CGPoint]) -> Bool { separation(a, from: b) != nil }

    /// How far to shift `moving` so it rests against, not inside, every obstacle.
    static func resolve(_ moving: [CGPoint], against obstacles: [[CGPoint]]) -> CGVector {
        var shift = CGVector.zero
        for _ in 0..<6 {
            var pushed = false
            for obstacle in obstacles {
                let placed = moving.map { CGPoint(x: $0.x + shift.dx, y: $0.y + shift.dy) }
                if let push = separation(placed, from: obstacle) {
                    shift.dx += push.dx
                    shift.dy += push.dy
                    pushed = true
                }
            }
            if !pushed { break }
        }
        return shift
    }

    /// Moves a tool from where it lies toward where the fingers would put it,
    /// the way a real one goes: it travels until it touches another tool and
    /// stops there, then slides along it and turns as far as it can. It is
    /// never pushed back or sideways, out from under the fingers.
    static func advance(from start: ToolPose, to goal: ToolPose, outline: (ToolPose) -> [CGPoint],
                        against obstacles: [[CGPoint]]) -> ToolPose {
        guard !obstacles.isEmpty else { return goal }
        func free(_ pose: ToolPose) -> Bool {
            let polygon = outline(pose)
            return !obstacles.contains { overlaps(polygon, $0) }
        }
        if free(goal) { return goal }
        // Already overlapping (laid down on top of one): free it the short way.
        guard free(start) else {
            let push = resolve(outline(goal), against: obstacles)
            return ToolPose(center: CGPoint(x: goal.center.x + push.dx, y: goal.center.y + push.dy), angle: goal.angle)
        }

        // As far along the way as it can go.
        var pose = farthest(from: start, to: goal, free: free)

        // Then slide: what is left of the move, less the part heading into what it touched.
        let pushes = obstacles.compactMap { separation(outline(goal), from: $0) }
        let n = pushes.reduce(CGVector.zero) { CGVector(dx: $0.dx + $1.dx, dy: $0.dy + $1.dy) }
        let nLength = hypot(Double(n.dx), Double(n.dy))
        var rest = (x: Double(goal.center.x - pose.center.x), y: Double(goal.center.y - pose.center.y))
        if nLength > 1e-9 {
            let nx = Double(n.dx) / nLength, ny = Double(n.dy) / nLength
            let into = rest.x * nx + rest.y * ny
            if into < 0 { rest = (rest.x - into * nx, rest.y - into * ny) }
        }
        let slid = ToolPose(center: CGPoint(x: Double(pose.center.x) + rest.x, y: Double(pose.center.y) + rest.y), angle: pose.angle)
        pose = farthest(from: pose, to: slid, free: free)

        // And turn as far as it will.
        pose = farthest(from: pose, to: ToolPose(center: pose.center, angle: goal.angle), free: free)
        return pose
    }

    /// The last pose on the way from `start` (free) to `goal` that is still free.
    private static func farthest(from start: ToolPose, to goal: ToolPose, free: (ToolPose) -> Bool) -> ToolPose {
        func at(_ t: Double) -> ToolPose {
            var turn = goal.angle - start.angle
            turn = atan2(sin(turn), cos(turn))
            return ToolPose(center: CGPoint(x: Double(start.center.x) + Double(goal.center.x - start.center.x) * t,
                                            y: Double(start.center.y) + Double(goal.center.y - start.center.y) * t),
                            angle: start.angle + turn * t)
        }
        if free(goal) { return goal }
        var lo = 0.0, hi = 1.0
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            if free(at(mid)) { lo = mid } else { hi = mid }
        }
        return at(lo)
    }

    private static func project(_ polygon: [CGPoint], _ axis: (x: Double, y: Double)) -> (Double, Double) {
        var lo = Double.infinity, hi = -Double.infinity
        for p in polygon {
            let d = Double(p.x) * axis.x + Double(p.y) * axis.y
            lo = min(lo, d)
            hi = max(hi, d)
        }
        return (lo, hi)
    }

    private static func centre(_ polygon: [CGPoint]) -> CGPoint {
        let n = Double(polygon.count)
        return CGPoint(x: polygon.reduce(0) { $0 + Double($1.x) } / n, y: polygon.reduce(0) { $0 + Double($1.y) } / n)
    }
}
