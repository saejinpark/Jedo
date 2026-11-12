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
        case .ruler, .setSquare45, .setSquare60, .protractor,
             .circleTemplate, .ellipseTemplate, .squareTemplate, .hexTemplate, .arcTemplate: true
        case .frenchCurveA, .frenchCurveB, .frenchCurveC, .hipCurve: false
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
