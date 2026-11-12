import CoreGraphics
import Foundation

/// Outlines of the curved tools, in millimetres about their middles.
enum CurveTools {
    // MARK: French curve (운형자)

    /// A French curve: a broad body that sweeps into a scroll, its curve
    /// tightening steadily toward the tip, so somewhere along its edges is a
    /// match for almost any gentle-to-tight bend. A slot through the body
    /// gives two more curves, inside.
    static let frenchCurveLengthMM = 150.0
    /// The centre line runs straight this far before it starts to bend.
    static let frenchCurveStraightMM = 35.0
    /// Radius of the centre line's bend at the tip.
    static let frenchCurveTipRadiusMM = 18.0
    static let frenchCurveWidthMM = (start: 46.0, end: 9.0)
    /// The slot: where along the centre line it runs, and how wide.
    static let frenchCurveSlotMM = (from: 12.0, to: 62.0, width: 10.0)

    /// Points along the centre line with its direction and the body's width there.
    static func frenchCurveSpine(step: Double = 0.5) -> [(point: CGPoint, angle: Double, width: Double)] {
        let length = frenchCurveLengthMM, straight = frenchCurveStraightMM
        let bendRate = 1 / frenchCurveTipRadiusMM / (length - straight)
        var out: [(CGPoint, Double, Double)] = []
        var x = 0.0, y = 0.0
        var s = 0.0
        while s <= length + 1e-9 {
            let bent = max(s - straight, 0)
            // Curving upward (y down), ever tighter: curvature grows along the bend.
            let angle = -bendRate * bent * bent / 2
            let t = s / length
            let width = frenchCurveWidthMM.end + (frenchCurveWidthMM.start - frenchCurveWidthMM.end) * pow(1 - t, 1.3)
            out.append((CGPoint(x: x, y: y), angle, width))
            x += cos(angle) * step
            y += sin(angle) * step
            s += step
        }
        return out
    }

    /// A band of the given widths along part of a centre line, with round ends,
    /// as a closed outline.
    static func band(_ spine: [(point: CGPoint, angle: Double, width: Double)], every: Int) -> [CGPoint] {
        func side(_ e: (point: CGPoint, angle: Double, width: Double), _ sign: Double) -> CGPoint {
            let n = (x: -sin(e.angle), y: cos(e.angle))
            return CGPoint(x: Double(e.point.x) + n.x * e.width / 2 * sign, y: Double(e.point.y) + n.y * e.width / 2 * sign)
        }
        func cap(_ e: (point: CGPoint, angle: Double, width: Double), from start: Double) -> [CGPoint] {
            (1..<12).map { k in
                let a = start + Double.pi * Double(k) / 12
                return CGPoint(x: Double(e.point.x) + cos(a) * e.width / 2, y: Double(e.point.y) + sin(a) * e.width / 2)
            }
        }
        let picked = stride(from: 0, to: spine.count, by: every).map { spine[$0] } + [spine[spine.count - 1]]
        let first = picked[0], last = picked[picked.count - 1]
        var out: [CGPoint] = picked.map { side($0, 1) }
        // Round the tip from the +side forward to the −side, and the start from the −side back to the +side.
        out += cap(last, from: last.angle - .pi / 2).reversed()
        out += picked.reversed().map { side($0, -1) }
        out += cap(first, from: first.angle + .pi / 2).reversed()
        return out
    }

    /// The outline and the slot, about the outline's middle.
    static let frenchCurveParts: (outline: [CGPoint], slot: [CGPoint]) = {
        let spine = frenchCurveSpine()
        let outline = band(spine, every: 2)
        let step = 0.5
        let slot = frenchCurveSlotMM
        let slotSpine = spine[Int(slot.from / step)...Int(slot.to / step)].map { ($0.point, $0.angle, slot.width) }
        let cut = band(Array(slotSpine), every: 2)
        let shift = centre(of: outline)
        return (outline.map { $0.minus(shift) }, cut.map { $0.minus(shift) })
    }()

    static var frenchCurveMM: [CGPoint] { frenchCurveParts.outline }
    static var frenchCurveSlotOutlineMM: [CGPoint] { frenchCurveParts.slot }

    // MARK: Hip curve

    static let hipCurveLengthMM = 600.0
    static let hipCurveWidthMM = 22.0
    /// How far the far end has risen above the near end.
    static let hipCurveRiseMM = 125.0

    /// The centre line, gentle at the start and bending more toward the end.
    static func hipCurveCentre(_ t: Double) -> CGPoint {
        CGPoint(x: hipCurveLengthMM * t, y: -hipCurveRiseMM * pow(t, 4))
    }

    /// The two long edges, start to end: the convex one (with the scale) first.
    static let hipCurveEdgesMM: (scale: [CGPoint], inner: [CGPoint]) = {
        let samples = 300
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
