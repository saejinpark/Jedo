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

    /// Takes to the edge within 2.5 mm and leaves it beyond 4 mm.
    static let standard = EdgeGuideStyle(captureMM: 2.5, releaseMM: 4)
}

/// Bends a stroke's samples onto the edge of whatever tool the pencil meets,
/// the way a pencil slides along a real ruler, set square or template hole.
/// Tools are solid: the pencil can never be on a tool's body. Near an edge,
/// depending on the style, the line takes to it.
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

    private(set) var attached: Attachment?
    /// Where the pencil last was on open paper.
    private var lastFree: CGPoint?

    init(style: EdgeGuideStyle, pixelsPerMillimeter ppmm: Double, contactOffset: Double) {
        captureDistance = style.captureMM * ppmm
        releaseDistance = style.releaseMM * ppmm
        self.contactOffset = contactOffset
    }

    mutating func guide(_ sample: StrokeSample, tools: [ToolShape]) -> StrokeSample {
        let p = sample.location

        // Resting against an edge: stay while pressed into the body or close outside.
        if let a = attached, a.tool < tools.count {
            let tool = tools[a.tool]
            let c = tool.contact(a.edge, at: p, offset: contactOffset)
            if c.alongside, c.distance <= releaseDistance, c.distance >= 0 || tool.covers(p) {
                return moved(sample, to: c.point)
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
                return moved(sample, to: tool.contact(edge, at: p, offset: contactOffset).point)
            }
            return sample
        }

        // On open paper: take to the closest edge within reach.
        lastFree = p
        var best: (Attachment, ToolShape.Contact)?
        for (i, tool) in tools.enumerated() {
            for edge in tool.guidingEdges {
                let c = tool.contact(edge, at: p, offset: contactOffset)
                guard c.alongside, c.distance >= 0, c.distance <= captureDistance else { continue }
                if best == nil || c.distance < best!.1.distance { best = (Attachment(tool: i, edge: edge), c) }
            }
        }
        if let (attachment, contact) = best {
            attached = attachment
            return moved(sample, to: contact.point)
        }
        return sample
    }

    /// The ruler alone, or nothing.
    mutating func guide(_ sample: StrokeSample, ruler: Ruler?) -> StrokeSample {
        guide(sample, tools: ruler.map { [$0.shape] } ?? [])
    }

    private func moved(_ sample: StrokeSample, to location: CGPoint) -> StrokeSample {
        var s = sample
        s.location = location
        return s
    }
}
