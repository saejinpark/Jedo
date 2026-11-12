import CoreGraphics
import Foundation

/// Outlines of the curved tools, in millimetres about their middles.
enum CurveTools {
    // MARK: French curve

    /// Points the French curve's outline passes through, going round it.
    /// Tight at the right end, long and gentle along the top, hollowed below.
    static let frenchCurveKnotsMM: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 30, y: -25), CGPoint(x: 75, y: -38), CGPoint(x: 125, y: -35),
        CGPoint(x: 170, y: -20), CGPoint(x: 200, y: 5), CGPoint(x: 205, y: 30), CGPoint(x: 185, y: 45),
        CGPoint(x: 150, y: 40), CGPoint(x: 120, y: 25), CGPoint(x: 95, y: 25), CGPoint(x: 75, y: 40),
        CGPoint(x: 55, y: 60), CGPoint(x: 30, y: 62), CGPoint(x: 10, y: 48), CGPoint(x: -5, y: 25),
    ]
    /// The curve as drawn is this fraction of the knots' size.
    static let frenchCurveScale = 0.72

    static let frenchCurveMM: [CGPoint] = {
        let knots = frenchCurveKnotsMM.map { $0.scaled(frenchCurveScale) }
        return centred(closedCatmullRom(knots, samplesPerSpan: 24))
    }()

    // MARK: Hip curve

    static let hipCurveLengthMM = 240.0
    static let hipCurveWidthMM = 32.0
    /// How far the far end has risen above the near end.
    static let hipCurveRiseMM = 40.0

    /// The centre line, gentle at the start and bending more toward the end.
    static func hipCurveCentre(_ t: Double) -> CGPoint {
        CGPoint(x: hipCurveLengthMM * t, y: -hipCurveRiseMM * pow(t, 2.4))
    }

    /// The two long edges, start to end: the convex one (with the scale) first.
    static let hipCurveEdgesMM: (scale: [CGPoint], inner: [CGPoint]) = {
        let samples = 160
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let c = hipCurveCentre(t)
            let ahead = hipCurveCentre(min(t + 0.001, 1)), behind = hipCurveCentre(max(t - 0.001, 0))
            let dx = Double(ahead.x - behind.x), dy = Double(ahead.y - behind.y)
            let length = hypot(dx, dy)
            // The side away from where the curve bends (below and right) is convex.
            let normal = (x: -dy / length, y: dx / length)
            let w = hipCurveWidthMM / 2
            outer.append(CGPoint(x: Double(c.x) + normal.x * w, y: Double(c.y) + normal.y * w))
            inner.append(CGPoint(x: Double(c.x) - normal.x * w, y: Double(c.y) - normal.y * w))
        }
        let shift = centre(of: outer + inner)
        return (outer.map { $0.minus(shift) }, inner.map { $0.minus(shift) })
    }()

    static let hipCurveMM: [CGPoint] = hipCurveEdgesMM.scale + hipCurveEdgesMM.inner.reversed()

    // MARK: Helpers

    /// A smooth closed curve through every knot.
    static func closedCatmullRom(_ knots: [CGPoint], samplesPerSpan: Int) -> [CGPoint] {
        let n = knots.count
        var out: [CGPoint] = []
        for i in 0..<n {
            let p0 = knots[(i - 1 + n) % n], p1 = knots[i], p2 = knots[(i + 1) % n], p3 = knots[(i + 2) % n]
            for s in 0..<samplesPerSpan {
                let t = Double(s) / Double(samplesPerSpan)
                let t2 = t * t, t3 = t2 * t
                func blend(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> Double {
                    0.5 * (2 * Double(b) + (Double(c) - Double(a)) * t
                        + (2 * Double(a) - 5 * Double(b) + 4 * Double(c) - Double(d)) * t2
                        + (3 * Double(b) - Double(a) - 3 * Double(c) + Double(d)) * t3)
                }
                out.append(CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        return out
    }

    /// The middle of the points' bounding box.
    static func centre(of points: [CGPoint]) -> CGPoint {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGPoint(x: ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, y: ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
    }

    static func centred(_ points: [CGPoint]) -> [CGPoint] {
        let c = centre(of: points)
        return points.map { $0.minus(c) }
    }
}

extension CGPoint {
    func minus(_ other: CGPoint) -> CGPoint { CGPoint(x: x - other.x, y: y - other.y) }
}
