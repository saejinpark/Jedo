import CoreGraphics
import Foundation

/// A point on a curved tool's centre line: where, which way, how wide there.
struct SpinePoint: Sendable {
    var point: CGPoint
    var angle: Double
    var width: Double
    /// Distance along the centre line, mm.
    var along: Double
}

/// A curved tool described the way a maker would: a centre line whose bend
/// changes along its length, and a width that tapers. Millimetres.
struct CurveProfile: Sendable {
    var lengthMM: Double
    /// Curvature (1/radius, per mm) at distances along the centre line, in
    /// order; linear in between. Positive bends upward (toward −y).
    var bends: [(at: Double, curvature: Double)]
    var width: (start: Double, end: Double)
    /// Above 1 keeps the body broad longer before it tapers.
    var widthExponent = 1.0

    func curvature(at s: Double) -> Double {
        guard let first = bends.first else { return 0 }
        if s <= first.at { return first.curvature }
        for (a, b) in zip(bends, bends.dropFirst()) where s <= b.at {
            let t = (s - a.at) / max(b.at - a.at, 1e-9)
            return a.curvature + (b.curvature - a.curvature) * t
        }
        return bends[bends.count - 1].curvature
    }

    func spine(step: Double = 0.5) -> [SpinePoint] {
        var out: [SpinePoint] = []
        var x = 0.0, y = 0.0, angle = 0.0, s = 0.0
        while s <= lengthMM + 1e-9 {
            let t = s / lengthMM
            let w = width.end + (width.start - width.end) * pow(1 - t, widthExponent)
            out.append(SpinePoint(point: CGPoint(x: x, y: y), angle: angle, width: w, along: s))
            // Half a step at the old heading, turn, half a step at the new: stays smooth.
            x += cos(angle) * step / 2
            y += sin(angle) * step / 2
            angle -= (curvature(at: s) + curvature(at: s + step)) / 2 * step
            x += cos(angle) * step / 2
            y += sin(angle) * step / 2
            s += step
        }
        return out
    }
}

/// Outlines of the curved tools, in millimetres about their middles.
enum CurveTools {
    /// One side of a band along the spine: +1 is the right of travel (the
    /// outside of an upward bend), −1 the left.
    static func side(_ e: SpinePoint, _ sign: Double, width: Double? = nil) -> CGPoint {
        let w = (width ?? e.width) / 2
        return CGPoint(x: Double(e.point.x) - sin(e.angle) * w * sign, y: Double(e.point.y) + cos(e.angle) * w * sign)
    }

    /// A closed outline round a band along `spine`, with round or square ends.
    static func band(_ spine: [SpinePoint], every: Int, width: Double? = nil, roundEnds: Bool = true) -> [CGPoint] {
        let picked = stride(from: 0, to: spine.count, by: every).map { spine[$0] } + [spine[spine.count - 1]]
        func cap(_ e: SpinePoint, from start: Double) -> [CGPoint] {
            let r = (width ?? e.width) / 2
            return (1..<12).map { k in
                let a = start + Double.pi * Double(k) / 12
                return CGPoint(x: Double(e.point.x) + cos(a) * r, y: Double(e.point.y) + sin(a) * r)
            }
        }
        let first = picked[0], last = picked[picked.count - 1]
        var out: [CGPoint] = picked.map { side($0, 1, width: width) }
        // Round the tip from the +side forward to the −side, and the start from the −side back.
        if roundEnds { out += cap(last, from: last.angle - .pi / 2).reversed() }
        out += picked.reversed().map { side($0, -1, width: width) }
        if roundEnds { out += cap(first, from: first.angle + .pi / 2).reversed() }
        return out
    }

    /// The middle of the points' bounding box.
    static func centre(of points: [CGPoint]) -> CGPoint {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGPoint(x: ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, y: ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
    }

    // MARK: Bamboo hip curve (대나무 곡자)

    /// Sixty centimetres, straight for most of its length; only the last
    /// hand span bends, more and more toward the end.
    static let hipCurveProfile = CurveProfile(
        lengthMM: 600,
        bends: [(0, 0), (400, 0), (600, 1 / 143.0)],
        width: (22, 22)
    )
    static var hipCurveLengthMM: Double { hipCurveProfile.lengthMM }
    static var hipCurveWidthMM: Double { hipCurveProfile.width.start }
    /// Where the bend begins.
    static let hipCurveStraightMM = 400.0

    /// The two long edges, start to end: the convex one (with the scale) first.
    static let hipCurveEdgesMM: (scale: [CGPoint], inner: [CGPoint]) = {
        let spine = hipCurveProfile.spine(step: 2)
        let outer = spine.map { side($0, 1) }, inner = spine.map { side($0, -1) }
        let shift = centre(of: outer + inner)
        return (outer.map { $0.minus(shift) }, inner.map { $0.minus(shift) })
    }()

    /// Square ends, as a bamboo rule is cut.
    static let hipCurveMM: [CGPoint] = hipCurveEdgesMM.scale + hipCurveEdgesMM.inner.reversed()
}

/// The classic set of three French curves (운형자), traced from a
/// public-domain drawing (see `FrenchCurveData`). Each has an outline of
/// steadily changing curvature and a cutout whose rim also guides.
enum FrenchCurve {
    struct Form: Sendable {
        let kind: ToolKind
        /// What it is called in the set.
        let name: String
        /// About the outline's middle, in millimetres.
        let outline: [CGPoint]
        let slots: [[CGPoint]]
    }

    static let forms: [Form] = [
        form(.frenchCurveA, "큰 것", FrenchCurveData.largeOutline, FrenchCurveData.largeCutout),
        form(.frenchCurveB, "중간", FrenchCurveData.mediumOutline, FrenchCurveData.mediumCutout),
        form(.frenchCurveC, "작은 것", FrenchCurveData.smallOutline, FrenchCurveData.smallCutout),
    ]

    private static func form(_ kind: ToolKind, _ name: String, _ outline: [(Double, Double)], _ cutout: [(Double, Double)]) -> Form {
        let rim = outline.map { CGPoint(x: $0.0, y: $0.1) }
        let shift = CurveTools.centre(of: rim)
        return Form(kind: kind, name: name, outline: rim.map { $0.minus(shift) },
                    slots: [cutout.map { CGPoint(x: $0.0, y: $0.1).minus(shift) }])
    }

    static func form(_ kind: ToolKind) -> Form? { forms.first { $0.kind == kind } }
    static func outline(_ kind: ToolKind) -> [CGPoint] { form(kind)?.outline ?? [] }
    static func slots(_ kind: ToolKind) -> [[CGPoint]] { form(kind)?.slots ?? [] }

    /// The point of the plastic farthest from any edge, where the set number goes.
    static let labelSpots: [ToolKind: CGPoint] = {
        var out: [ToolKind: CGPoint] = [:]
        for form in forms {
            let shape = ToolShape(pose: ToolPose(center: .zero, angle: 0), outline: form.outline, smooth: true, cutouts: form.slots)
            let xs = form.outline.map(\.x), ys = form.outline.map(\.y)
            var best = (point: CGPoint.zero, room: -1.0)
            for x in stride(from: Double(xs.min() ?? 0), through: Double(xs.max() ?? 0), by: 1.5) {
                for y in stride(from: Double(ys.min() ?? 0), through: Double(ys.max() ?? 0), by: 1.5) {
                    let p = CGPoint(x: x, y: y)
                    guard shape.covers(p) else { continue }
                    let room = shape.guidingEdges.map { -shape.contact($0, at: p, offset: 0).distance }.min() ?? 0
                    if room > best.room { best = (p, room) }
                }
            }
            out[form.kind] = best.point
        }
        return out
    }()

    static func labelSpot(_ kind: ToolKind) -> CGPoint { labelSpots[kind] ?? .zero }
}

extension CGPoint {
    func minus(_ other: CGPoint) -> CGPoint { CGPoint(x: x - other.x, y: y - other.y) }
}
