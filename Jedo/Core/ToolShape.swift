import CoreGraphics
import Foundation

/// Where a tool lies on the paper: its own origin and how far it is turned.
typealias ToolPose = RulerPose

/// The solid body of a rigid drafting tool and the edges a pencil can run
/// along. Round holes are paper the pencil can reach.
///
/// A straight-sided tool (ruler, set square) has a convex outline whose
/// sides guide one by one. A curved tool (French curve, hip curve) has a
/// finely sampled outline, convex or not, that guides as one smooth edge.
/// Lengths are canvas pixels; `outline` and `holes` are in the tool's own frame.
struct ToolShape: Equatable, Sendable {
    struct Hole: Equatable, Sendable {
        var center: CGPoint
        var radius: Double
    }

    /// An edge the pencil can rest against.
    enum Edge: Hashable, Sendable {
        /// The outline from corner `i` to corner `i + 1`.
        case side(Int)
        case hole(Int)
        /// The whole outline of a curved tool.
        case boundary
        /// The rim of a cut-out slot in a curved tool.
        case cutout(Int)
    }

    /// Where the pencil stands relative to one edge.
    struct Contact: Equatable, Sendable {
        /// How far the pencil is on the paper side of the edge; negative is onto the body.
        var distance: Double
        /// Whether the pencil is level with the edge, between its ends.
        var alongside: Bool
        /// Where the lead's centre sits resting against the edge.
        var point: CGPoint
        /// The edge's direction there, a unit vector on the paper (either way along it).
        var tangent: (x: Double, y: Double)

        static func == (a: Contact, b: Contact) -> Bool {
            a.distance == b.distance && a.alongside == b.alongside && a.point == b.point
                && a.tangent.x == b.tangent.x && a.tangent.y == b.tangent.y
        }
    }

    var pose: ToolPose
    var outline: [CGPoint]
    /// Whether each side of the outline guides the pencil.
    var guidingSides: [Bool]
    var holes: [Hole] = []
    /// Whether the outline is a sampled curve that guides as one edge.
    var smooth = false
    /// Slots cut through the body, each a sampled closed curve whose rim guides.
    var cutouts: [[CGPoint]] = []

    init(pose: ToolPose, outline: [CGPoint], guidingSides: [Bool]? = nil, holes: [Hole] = [], smooth: Bool = false,
         cutouts: [[CGPoint]] = []) {
        precondition(outline.count >= 3)
        self.pose = pose
        self.outline = outline
        self.guidingSides = guidingSides ?? Array(repeating: true, count: outline.count)
        self.holes = holes
        self.smooth = smooth
        self.cutouts = cutouts
    }

    /// Every edge a pencil can be guided by.
    var guidingEdges: [Edge] {
        let rim: [Edge] = smooth ? [.boundary] : outline.indices.filter { guidingSides[$0] }.map(Edge.side)
        return rim + holes.indices.map(Edge.hole) + cutouts.indices.map(Edge.cutout)
    }

    // MARK: Frames

    func local(_ p: CGPoint) -> CGPoint {
        let dx = Double(p.x - pose.center.x), dy = Double(p.y - pose.center.y)
        let c = cos(pose.angle), s = sin(pose.angle)
        return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
    }

    /// A direction in the tool's frame, turned onto the paper.
    func worldDirection(_ d: (x: Double, y: Double)) -> (x: Double, y: Double) {
        let c = cos(pose.angle), s = sin(pose.angle)
        return (d.x * c - d.y * s, d.x * s + d.y * c)
    }

    func world(_ q: CGPoint) -> CGPoint {
        let c = cos(pose.angle), s = sin(pose.angle)
        return CGPoint(x: Double(pose.center.x) + Double(q.x) * c - Double(q.y) * s,
                       y: Double(pose.center.y) + Double(q.x) * s + Double(q.y) * c)
    }

    // MARK: Body

    /// Whether `p` lies within the outline grown by `margin`, holes included.
    func outlineContains(_ p: CGPoint, margin: Double = 0) -> Bool {
        let q = local(p)
        if inside(q) { return true }
        return margin > 0 && nearestOnOutline(q).distance <= margin
    }

    /// Whether local point `q` is inside the outline (even–odd, so any simple outline works).
    private func inside(_ q: CGPoint) -> Bool { Self.inside(q, outline) }

    private func nearestOnOutline(_ q: CGPoint) -> (point: CGPoint, distance: Double, dir: (x: Double, y: Double)) {
        Self.nearest(q, on: outline)
    }

    private static func inside(_ q: CGPoint, _ polygon: [CGPoint]) -> Bool {
        var result = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > q.y) != (b.y > q.y) {
                let x = Double(a.x) + Double(q.y - a.y) / Double(b.y - a.y) * Double(b.x - a.x)
                if Double(q.x) < x { result.toggle() }
            }
            j = i
        }
        return result
    }

    /// The closest point on a closed polygon to local point `q`, and the polygon's direction there.
    private static func nearest(_ q: CGPoint, on polygon: [CGPoint]) -> (point: CGPoint, distance: Double, dir: (x: Double, y: Double)) {
        var best = (point: polygon[0], distance: Double.infinity, dir: (x: 1.0, y: 0.0))
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let ex = Double(b.x - a.x), ey = Double(b.y - a.y)
            let lengthSquared = ex * ex + ey * ey
            guard lengthSquared > 0 else { continue }
            let t = min(max((Double(q.x - a.x) * ex + Double(q.y - a.y) * ey) / lengthSquared, 0), 1)
            let px = Double(a.x) + ex * t, py = Double(a.y) + ey * t
            let d = hypot(Double(q.x) - px, Double(q.y) - py)
            if d < best.distance {
                let length = lengthSquared.squareRoot()
                best = (CGPoint(x: px, y: py), d, (ex / length, ey / length))
            }
        }
        return best
    }

    /// Whether `p` is on the tool's body, where the pencil cannot reach the paper.
    func covers(_ p: CGPoint) -> Bool {
        guard outlineContains(p) else { return false }
        let q = local(p)
        if holes.contains(where: { hypot(Double(q.x - $0.center.x), Double(q.y - $0.center.y)) < $0.radius }) { return false }
        return !cutouts.contains { Self.inside(q, $0) }
    }

    // MARK: Edges

    /// Where the pencil at `p` stands against `edge`, with the lead's centre
    /// `offset` pixels out onto the paper.
    func contact(_ edge: Edge, at p: CGPoint, offset: Double) -> Contact {
        let q = local(p)
        switch edge {
        case .side(let i):
            let s = side(at: i, q)
            let point = CGPoint(x: Double(s.a.x) + s.dir.x * s.t + s.normal.x * offset,
                                y: Double(s.a.y) + s.dir.y * s.t + s.normal.y * offset)
            return Contact(distance: s.distance, alongside: s.t >= 0 && s.t <= s.length, point: world(point),
                           tangent: worldDirection(s.dir))
        case .hole(let i):
            let hole = holes[i]
            var vx = Double(q.x - hole.center.x), vy = Double(q.y - hole.center.y)
            var r = hypot(vx, vy)
            if r < 1e-9 { (vx, vy, r) = (1, 0, 1e-9) }
            let reach = hole.radius - offset
            let point = CGPoint(x: Double(hole.center.x) + vx / max(r, 1e-9) * reach,
                                y: Double(hole.center.y) + vy / max(r, 1e-9) * reach)
            return Contact(distance: hole.radius - r, alongside: true, point: world(point),
                           tangent: worldDirection((x: -vy / max(r, 1e-9), y: vx / max(r, 1e-9))))
        case .boundary:
            // The paper is outside the outline.
            return rimContact(q, polygon: outline, paperInside: false, offset: offset)
        case .cutout(let i):
            // The paper is inside the slot.
            return rimContact(q, polygon: cutouts[i], paperInside: true, offset: offset)
        }
    }

    /// Where local point `q` stands against a sampled closed rim.
    private func rimContact(_ q: CGPoint, polygon: [CGPoint], paperInside: Bool, offset: Double) -> Contact {
        let n = Self.nearest(q, on: polygon)
        let isInside = Self.inside(q, polygon)
        let onPaper = isInside == paperInside
        // A unit vector from the rim toward the paper.
        var toPaper: (x: Double, y: Double)
        if n.distance > 1e-6 {
            let v = (x: (Double(q.x) - Double(n.point.x)) / n.distance, y: (Double(q.y) - Double(n.point.y)) / n.distance)
            toPaper = onPaper ? v : (-v.x, -v.y)
        } else {
            toPaper = (n.dir.y, -n.dir.x)
            let probe = CGPoint(x: Double(n.point.x) + toPaper.x * 0.5, y: Double(n.point.y) + toPaper.y * 0.5)
            if Self.inside(probe, polygon) != paperInside { toPaper = (-toPaper.x, -toPaper.y) }
        }
        let point = CGPoint(x: Double(n.point.x) + toPaper.x * offset, y: Double(n.point.y) + toPaper.y * offset)
        return Contact(distance: onPaper ? n.distance : -n.distance, alongside: true, point: world(point),
                       tangent: worldDirection(n.dir))
    }

    /// Side `i` measured from local point `q`: position along it, distance outward.
    private func side(at i: Int, _ q: CGPoint)
        -> (a: CGPoint, dir: (x: Double, y: Double), normal: (x: Double, y: Double), length: Double, t: Double, distance: Double) {
        let a = outline[i], b = outline[(i + 1) % outline.count]
        let ex = Double(b.x - a.x), ey = Double(b.y - a.y)
        let length = max(hypot(ex, ey), 1e-9)
        let dir = (x: ex / length, y: ey / length)
        // Outward: away from the outline's centre.
        var normal = (x: dir.y, y: -dir.x)
        let toCentre = (x: Double(centroid.x - a.x), y: Double(centroid.y - a.y))
        if normal.x * toCentre.x + normal.y * toCentre.y > 0 { normal = (-normal.x, -normal.y) }
        let rx = Double(q.x - a.x), ry = Double(q.y - a.y)
        return (a, dir, normal, length, rx * dir.x + ry * dir.y, rx * normal.x + ry * normal.y)
    }

    private var centroid: CGPoint {
        let n = Double(outline.count)
        return CGPoint(x: outline.reduce(0) { $0 + Double($1.x) } / n, y: outline.reduce(0) { $0 + Double($1.y) } / n)
    }
}
