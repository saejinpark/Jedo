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

/// A set of French curves (운형자): each a broad body sweeping into curves of
/// steadily changing bend, with slots through it whose rims also guide.
/// Between them, somewhere along an edge is a match for almost any curve.
enum FrenchCurve {
    struct Slot: Sendable {
        var from: Double
        var to: Double
        var width: Double
    }

    struct Form: Sendable {
        let kind: ToolKind
        /// What it is called in the set.
        let name: String
        let profile: CurveProfile
        let slots: [Slot]
    }

    static let forms: [Form] = [
        Form(kind: .frenchCurveA, name: "말림",
             profile: CurveProfile(lengthMM: 150, bends: [(0, 0), (35, 0), (150, 1 / 18.0)], width: (46, 9), widthExponent: 1.3),
             slots: [Slot(from: 12, to: 62, width: 10)]),
        Form(kind: .frenchCurveB, name: "S자",
             profile: CurveProfile(lengthMM: 170, bends: [(0, 1 / 55.0), (60, 0), (170, -1 / 24.0)], width: (36, 10), widthExponent: 1.2),
             slots: [Slot(from: 18, to: 66, width: 8)]),
        Form(kind: .frenchCurveC, name: "완만",
             profile: CurveProfile(lengthMM: 210, bends: [(0, 1 / 600.0), (210, 1 / 48.0)], width: (30, 12)),
             slots: [Slot(from: 22, to: 105, width: 9), Slot(from: 125, to: 165, width: 6)]),
        Form(kind: .frenchCurveD, name: "작은 말림",
             profile: CurveProfile(lengthMM: 100, bends: [(0, 0), (100, 1 / 14.0)], width: (30, 7), widthExponent: 1.4),
             slots: [Slot(from: 10, to: 40, width: 7)]),
    ]

    static func form(_ kind: ToolKind) -> Form? { forms.first { $0.kind == kind } }

    /// Each form's outline and slots, about the outline's middle.
    static let parts: [ToolKind: (outline: [CGPoint], slots: [[CGPoint]])] = {
        var out: [ToolKind: (outline: [CGPoint], slots: [[CGPoint]])] = [:]
        for form in forms {
            let step = 0.5
            let spine = form.profile.spine(step: step)
            let outline = CurveTools.band(spine, every: 2)
            let slots = form.slots.map { slot in
                CurveTools.band(Array(spine[Int(slot.from / step)...Int(slot.to / step)]), every: 2, width: slot.width)
            }
            let shift = CurveTools.centre(of: outline)
            out[form.kind] = (outline.map { $0.minus(shift) }, slots.map { $0.map { $0.minus(shift) } })
        }
        return out
    }()

    static func outline(_ kind: ToolKind) -> [CGPoint] { parts[kind]?.outline ?? [] }
    static func slots(_ kind: ToolKind) -> [[CGPoint]] { parts[kind]?.slots ?? [] }
}

extension CGPoint {
    func minus(_ other: CGPoint) -> CGPoint { CGPoint(x: x - other.x, y: y - other.y) }
}
