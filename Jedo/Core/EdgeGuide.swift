import CoreGraphics
import Foundation

/// When the pencil's line follows the ruler's edge. These are drafts to
/// compare by hand; the app lets you switch between them.
struct EdgeGuideStyle: Equatable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    /// How close outside the edge the pencil must come for the line to take to it.
    var captureMM: Double
    /// How far outside the edge the pencil may wander before the line leaves it.
    var releaseMM: Double

    /// Once the line is on the edge it stays there until the pencil lifts.
    static let stickUntilLift = EdgeGuideStyle(name: "끝까지 붙음", captureMM: 2.5, releaseMM: .infinity)
    /// The line follows the edge while the pencil stays near it, and leaves if pulled away.
    static let letGo = EdgeGuideStyle(name: "떼면 떨어짐", captureMM: 2.5, releaseMM: 4)
    /// No pull at all: the ruler only stops the pencil from crossing it.
    static let blockOnly = EdgeGuideStyle(name: "막히기만", captureMM: 0, releaseMM: 0)

    static let all: [EdgeGuideStyle] = [.stickUntilLift, .letGo, .blockOnly]
    static let `default` = letGo
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
