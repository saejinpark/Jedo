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
        /// Both, by what the hand does: let go before drawing and it stays
        /// planted; hold it through a circle and it comes out with the finger.
        case byHand
    }

    var spread: Spread
    var needle: Needle

    /// The brief's first draft.
    static let firstDraft = CompassStyle(spread: .eachTouch, needle: .whileHeld)
    /// What the app uses (2026-11-13): the legs keep their spread, as a real
    /// compass's joint does, and the needle stays or goes by how it was held.
    static let standard = CompassStyle(spread: .kept, needle: .byHand)

    /// Whether lifting the finger that planted the needle pulls it out,
    /// given whether the compass has drawn since.
    func pullsNeedleOnLift(afterDrawing drew: Bool) -> Bool {
        switch needle {
        case .whileHeld: true
        case .planted: false
        case .byHand: drew
        }
    }
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

    /// Whether `point` is on the needle's head, close enough to take hold of it.
    func needleHeadContains(_ point: CGPoint, radius: Double) -> Bool {
        hypot(Double(point.x - needle.x), Double(point.y - needle.y)) <= radius
    }
}
