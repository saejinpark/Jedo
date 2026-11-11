import CoreGraphics
import Foundation

/// When the pencil's line follows the ruler's edge.
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

/// Bends a stroke's samples onto the ruler's edge, the way a pencil slides
/// along a real one. The ruler is a solid body: the pencil can never be
/// under it. Near an edge, depending on the style, the line takes to it.
///
/// One guide lives for one stroke. It is a value type, so a copy can run
/// ahead over predicted touches without changing the real stroke.
struct EdgeGuide: Sendable {
    let captureDistance: Double
    let releaseDistance: Double
    /// The lead's centre sits this far outside the edge it rests against.
    let contactOffset: Double

    private(set) var attached: Ruler.Edge?
    /// Which side of the ruler the pencil was last seen on in the open.
    private var lastSide: Ruler.Edge?

    init(style: EdgeGuideStyle, pixelsPerMillimeter ppmm: Double, contactOffset: Double) {
        captureDistance = style.captureMM * ppmm
        releaseDistance = style.releaseMM * ppmm
        self.contactOffset = contactOffset
    }

    mutating func guide(_ sample: StrokeSample, ruler: Ruler?) -> StrokeSample {
        guard let ruler else {
            attached = nil
            return sample
        }
        let (u, v) = ruler.local(sample.location)

        // Past the ends nothing guides the pencil.
        guard ruler.spans(u: u) else {
            attached = nil
            lastSide = Ruler.side(ofV: v)
            return sample
        }

        // Under the ruler: the pencil is held against the edge it came from.
        if abs(v) <= ruler.width / 2 {
            let edge = attached ?? lastSide ?? Ruler.side(ofV: v)
            attached = edge
            return moved(sample, to: ruler.pointAlong(edge, u: u, offset: contactOffset))
        }

        let side = Ruler.side(ofV: v)
        let distance = ruler.outsideDistance(v: v, from: side)

        if let edge = attached, edge == side, distance <= releaseDistance {
            return moved(sample, to: ruler.pointAlong(edge, u: u, offset: contactOffset))
        }
        attached = nil
        lastSide = side

        if distance <= captureDistance {
            attached = side
            return moved(sample, to: ruler.pointAlong(side, u: u, offset: contactOffset))
        }
        return sample
    }

    private func moved(_ sample: StrokeSample, to location: CGPoint) -> StrokeSample {
        var s = sample
        s.location = location
        return s
    }
}
