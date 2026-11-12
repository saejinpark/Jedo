import CoreGraphics
import Foundation

/// Where a tool lies on the paper: its own origin and how far it is turned.
typealias ToolPose = RulerPose

/// The solid body of a rigid drafting tool and the edges a pencil can run
/// along. The outline is convex; round holes are paper the pencil can reach.
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
    }

    /// Where the pencil stands relative to one edge.
    struct Contact: Equatable, Sendable {
        /// How far the pencil is on the paper side of the edge; negative is onto the body.
        var distance: Double
        /// Whether the pencil is level with the edge, between its ends.
        var alongside: Bool
        /// Where the lead's centre sits resting against the edge.
        var point: CGPoint
    }

    var pose: ToolPose
    var outline: [CGPoint]
    /// Whether each side of the outline guides the pencil.
    var guidingSides: [Bool]
    var holes: [Hole] = []

    init(pose: ToolPose, outline: [CGPoint], guidingSides: [Bool]? = nil, holes: [Hole] = []) {
        precondition(outline.count >= 3)
        self.pose = pose
        self.outline = outline
        self.guidingSides = guidingSides ?? Array(repeating: true, count: outline.count)
        self.holes = holes
    }

    /// Every edge a pencil can be guided by.
    var guidingEdges: [Edge] {
        outline.indices.filter { guidingSides[$0] }.map(Edge.side) + holes.indices.map(Edge.hole)
    }

    // MARK: Frames

    func local(_ p: CGPoint) -> CGPoint {
        let dx = Double(p.x - pose.center.x), dy = Double(p.y - pose.center.y)
        let c = cos(pose.angle), s = sin(pose.angle)
        return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
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
        return outline.indices.allSatisfy { side(at: $0, q).distance <= margin }
    }

    /// Whether `p` is on the tool's body, where the pencil cannot reach the paper.
    func covers(_ p: CGPoint) -> Bool {
        guard outlineContains(p) else { return false }
        let q = local(p)
        return !holes.contains { hypot(Double(q.x - $0.center.x), Double(q.y - $0.center.y)) < $0.radius }
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
            return Contact(distance: s.distance, alongside: s.t >= 0 && s.t <= s.length, point: world(point))
        case .hole(let i):
            let hole = holes[i]
            var vx = Double(q.x - hole.center.x), vy = Double(q.y - hole.center.y)
            var r = hypot(vx, vy)
            if r < 1e-9 { (vx, vy, r) = (1, 0, 1e-9) }
            let reach = hole.radius - offset
            let point = CGPoint(x: Double(hole.center.x) + vx / max(r, 1e-9) * reach,
                                y: Double(hole.center.y) + vy / max(r, 1e-9) * reach)
            return Contact(distance: hole.radius - r, alongside: true, point: world(point))
        }
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
