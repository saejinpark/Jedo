import CoreGraphics
import Foundation

/// When the pencil's line follows a tool's edge.
///
/// Three drafts were compared on a real iPad: stick until the pencil lifts,
/// let go when pulled away, and block only (no pull). Letting go was chosen.
struct EdgeGuideStyle: Equatable, Sendable {
    /// How close outside the edge the pencil must come for the line to take to it.
    var captureMM: Double
    /// How far outside the edge the pencil may wander before the line leaves it.
    var releaseMM: Double

    /// Like a real edge: it stops the pencil going into the tool, and the
    /// line takes to it only when the lead is all but touching (0.5 mm) and
    /// leaves as soon as it is drawn away (1.2 mm). Pressing toward the tool
    /// keeps the line on the edge for as long as you like, as with a real ruler.
    static let standard = EdgeGuideStyle(captureMM: 0.5, releaseMM: 1.2)

    /// The first draft: took to the edge within 2.5 mm and left beyond 4 mm.
    /// On the iPad it felt like a magnet pulling the line in.
    static let magnetic = EdgeGuideStyle(captureMM: 2.5, releaseMM: 4)
}

/// Bends a stroke's samples onto the edge of whatever tool the pencil meets,
/// the way a pencil slides along a real ruler, set square or template hole.
/// Tools are solid: the pencil can never be on a tool's body. Near an edge,
/// depending on the style, the line takes to it.
///
/// The line never jumps. Taking to an edge or leaving it opens a gap between
/// where the line was heading and where it now belongs; the line closes that
/// gap gradually as the pencil travels on, so it eases onto and off the edge.
///
/// Once a stroke is under way, the line only takes to an edge the pencil is
/// running along. A line crossing past an edge, or drawn toward it and away,
/// stays as drawn.
///
/// One guide lives for one stroke. It is a value type, so a copy can run
/// ahead over predicted touches without changing the real stroke.
struct EdgeGuide: Sendable {
    struct Attachment: Equatable, Sendable {
        /// Index into the tools passed to `guide`.
        var tool: Int
        var edge: ToolShape.Edge
    }

    let captureDistance: Double
    let releaseDistance: Double
    /// The lead's centre sits this far out from the edge it rests against.
    let contactOffset: Double
    /// How far the pencil travels before the stroke counts as under way, and
    /// over how much travel its direction is read.
    let settleDistance: Double

    /// Gap closed per pixel the pencil travels: 1 eases in at about 45°.
    static let easeRate = 1.0
    /// Mid-stroke, the pencil must run within this angle of an edge to take to it.
    static let alongAngleDegrees = 30.0
    static let settleMM = 1.0

    private(set) var attached: Attachment?
    /// Where the pencil last was on open paper.
    private var lastFree: CGPoint?
    private var lastInput: CGPoint?
    private var lastOutput: CGPoint?
    /// The part of the line's position still being eased away.
    private var carry: (x: Double, y: Double) = (0, 0)
    private var travelled = 0.0
    private var headingFrom: CGPoint?
    private var heading: (x: Double, y: Double)?

    init(style: EdgeGuideStyle, pixelsPerMillimeter ppmm: Double, contactOffset: Double) {
        captureDistance = style.captureMM * ppmm
        releaseDistance = style.releaseMM * ppmm
        self.contactOffset = contactOffset
        settleDistance = Self.settleMM * ppmm
    }

    mutating func guide(_ sample: StrokeSample, tools: [ToolShape]) -> StrokeSample {
        let p = sample.location
        let step = lastInput.map { hypot(Double(p.x - $0.x), Double(p.y - $0.y)) } ?? 0
        travelled += step
        trackHeading(p)

        let before = attached
        let target = place(p, tools: tools)

        if attached != before, let lastInput, let lastOutput {
            // Carry on from where the line was heading, and ease from there.
            let onward = (x: Double(lastOutput.x) + Double(p.x - lastInput.x), y: Double(lastOutput.y) + Double(p.y - lastInput.y))
            carry = (onward.x - Double(target.x), onward.y - Double(target.y))
        } else {
            let gap = hypot(carry.x, carry.y)
            let left = max(gap - step * Self.easeRate, 0)
            carry = gap > 0 ? (carry.x * left / gap, carry.y * left / gap) : (0, 0)
        }

        var out = CGPoint(x: Double(target.x) + carry.x, y: Double(target.y) + carry.y)
        if tools.contains(where: { $0.covers(out) }) {
            // Easing must never take the lead onto a tool.
            carry = (0, 0)
            out = target
        }
        lastInput = p
        lastOutput = out
        var s = sample
        s.location = out
        return s
    }

    /// The ruler alone, or nothing.
    mutating func guide(_ sample: StrokeSample, ruler: Ruler?) -> StrokeSample {
        guide(sample, tools: ruler.map { [$0.shape] } ?? [])
    }

    /// Where the lead belongs for the pencil at `p`, before any easing.
    private mutating func place(_ p: CGPoint, tools: [ToolShape]) -> CGPoint {
        // Resting against an edge: stay while pressed into the body or close outside.
        if let a = attached, a.tool < tools.count {
            let tool = tools[a.tool]
            let c = tool.contact(a.edge, at: p, offset: contactOffset)
            if c.alongside, c.distance <= releaseDistance, c.distance >= 0 || tool.covers(p) {
                return c.point
            }
        }
        attached = nil

        // On a tool's body: the pencil is held against the edge it came from.
        if let i = tools.indices.last(where: { tools[$0].covers(p) }) {
            let tool = tools[i]
            let reference = lastFree ?? p
            let edges = tool.guidingEdges.filter { tool.contact($0, at: p, offset: contactOffset).alongside }
            if let edge = edges.min(by: {
                abs(tool.contact($0, at: reference, offset: 0).distance) < abs(tool.contact($1, at: reference, offset: 0).distance)
            }) {
                attached = Attachment(tool: i, edge: edge)
                return tool.contact(edge, at: p, offset: contactOffset).point
            }
            return p
        }

        // On open paper: take to the closest edge within reach that the pencil runs along.
        lastFree = p
        var best: (Attachment, ToolShape.Contact)?
        for (i, tool) in tools.enumerated() {
            for edge in tool.guidingEdges {
                let c = tool.contact(edge, at: p, offset: contactOffset)
                guard c.alongside, c.distance >= 0, c.distance <= captureDistance, runsAlong(c.tangent) else { continue }
                if best == nil || c.distance < best!.1.distance { best = (Attachment(tool: i, edge: edge), c) }
            }
        }
        if let (attachment, contact) = best {
            attached = attachment
            return contact.point
        }
        return p
    }

    /// At the start of a stroke any edge within reach will do: the pencil was
    /// put down against it. After that, only one the pencil is running along.
    private func runsAlong(_ tangent: (x: Double, y: Double)) -> Bool {
        guard travelled >= settleDistance, let heading else { return true }
        return abs(heading.x * tangent.x + heading.y * tangent.y) >= cos(Self.alongAngleDegrees * .pi / 180)
    }

    private mutating func trackHeading(_ p: CGPoint) {
        guard let from = headingFrom else {
            headingFrom = p
            return
        }
        let dx = Double(p.x - from.x), dy = Double(p.y - from.y)
        let length = hypot(dx, dy)
        guard length >= settleDistance else { return }
        heading = (dx / length, dy / length)
        headingFrom = p
    }
}
