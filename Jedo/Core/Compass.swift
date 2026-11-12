import CoreGraphics
import Foundation

/// How the compass is handled. These are hand-feel drafts still being compared.
struct CompassStyle: Equatable, Sendable {
    /// What sets the compass's spread when the pencil touches down.
    enum Spread: Equatable, Sendable, CaseIterable {
        /// Wherever the pencil lands sets a new spread (the first draft).
        case eachTouch
        /// The legs keep their spread: landing near it draws the same circle again.
        case kept
    }

    /// What keeps the needle in the paper.
    enum Needle: Equatable, Sendable, CaseIterable {
        /// Only while the finger that planted it stays down (the first draft).
        case whileHeld
        /// It stays planted until a finger taps it away.
        case planted
    }

    var spread: Spread
    var needle: Needle

    /// The brief's first draft.
    static let firstDraft = CompassStyle(spread: .eachTouch, needle: .whileHeld)
}

/// A drafting compass on the paper: the needle's point and how far the legs
/// are spread. Canvas pixels and radians.
struct Compass: Equatable, Sendable {
    /// Where the needle is planted.
    var needle: CGPoint
    /// Distance from needle to lead; nil while the legs are closed.
    var spread: Double?
    /// Direction from the needle to where the lead last rested.
    var leadAngle: Double = -.pi / 4

    /// A bow compass closes to about this.
    static let minSpreadMM = 1.5
    /// A drafting compass with its extension bar reaches about this.
    static let maxSpreadMM = 150.0
    /// With kept spread, landing this close to the spread's circle uses it.
    static let keepSpreadMM = 1.5

    init(needle: CGPoint, spread: Double? = nil, leadAngle: Double = -.pi / 4) {
        self.needle = needle
        self.spread = spread
        self.leadAngle = leadAngle
    }

    /// Where the lead rests, if the legs are open.
    var lead: CGPoint? {
        spread.map { CGPoint(x: Double(needle.x) + cos(leadAngle) * $0, y: Double(needle.y) + sin(leadAngle) * $0) }
    }

    /// The spread a stroke starting at `point` uses, or nil if the compass
    /// can't reach it and the pencil draws on its own.
    func spread(forPencilAt point: CGPoint, keepsSpread: Bool, pixelsPerMillimeter ppmm: Double) -> Double? {
        let distance = hypot(Double(point.x - needle.x), Double(point.y - needle.y))
        if keepsSpread, let spread, abs(distance - spread) <= Self.keepSpreadMM * ppmm {
            return spread
        }
        guard distance >= Self.minSpreadMM * ppmm, distance <= Self.maxSpreadMM * ppmm else { return nil }
        return distance
    }

    /// Lying closed on the paper, the legs run this way from the handle, this far.
    static let closedAngle = Double.pi / 2 + 0.35
    static let closedLengthMM = 60.0

    /// Whether `point` is on the compass lying on the paper (or within `margin`
    /// of it): its handle, and its legs open or closed.
    func bodyContains(_ point: CGPoint, margin: Double, pixelsPerMillimeter ppmm: Double) -> Bool {
        let tips: [CGPoint]
        if let lead {
            tips = [lead]
        } else {
            let reach = Self.closedLengthMM * ppmm
            tips = [CGPoint(x: Double(needle.x) + cos(Self.closedAngle) * reach, y: Double(needle.y) + sin(Self.closedAngle) * reach)]
        }
        if hypot(Double(point.x - needle.x), Double(point.y - needle.y)) <= 3 * ppmm + margin { return true }
        return tips.contains { Self.distance(from: point, toSegment: needle, $0) <= 1.5 * ppmm + margin }
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let ex = Double(b.x - a.x), ey = Double(b.y - a.y)
        let lengthSquared = ex * ex + ey * ey
        guard lengthSquared > 0 else { return hypot(Double(p.x - a.x), Double(p.y - a.y)) }
        let t = min(max((Double(p.x - a.x) * ex + Double(p.y - a.y) * ey) / lengthSquared, 0), 1)
        return hypot(Double(p.x - a.x) - ex * t, Double(p.y - a.y) - ey * t)
    }

    /// Whether `point` is on the needle's head, close enough to take hold of it.
    func needleHeadContains(_ point: CGPoint, radius: Double) -> Bool {
        hypot(Double(point.x - needle.x), Double(point.y - needle.y)) <= radius
    }
}
