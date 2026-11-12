import Foundation

/// The point of a pencil lead and how it wears.
///
/// The point is a cone; drawing wears flat whichever side of it touches the
/// paper, and a worn side lays a wider, greyer line. Drafters turn the
/// pencil as they draw so the cone wears evenly and the line keeps its
/// width (see DESIGN.md). Here the cone's round is six sides: the side
/// touching follows how the pencil is turned in the hand, from Apple
/// Pencil Pro's barrel roll or, without it, a double-tap that turns it a
/// sixth. Sharpening brings every side back to a point.
struct LeadPoint: Equatable, Sendable {
    static let sides = 6

    /// Wear of each side, 0 sharp ... 1 worn flat.
    private(set) var wear = [Double](repeating: 0, count: LeadPoint.sides)
    /// How far the pencil is turned in the hand, in sixths, for pencils that can't sense it.
    private(set) var turned = 0

    /// Millimetres of line at medium pressure that wear one side flat.
    /// Hard leads hold a point far longer than soft ones.
    static func lifeMM(_ grade: PencilGrade) -> Double {
        switch grade {
        case .h4: 1500
        case .h2: 1100
        case .h: 850
        case .f: 650
        case .hb: 500
        case .b: 400
        case .b2: 320
        case .b3: 260
        case .b4: 210
        case .b5: 170
        case .b6: 140
        }
    }

    /// The side touching the paper: from the barrel's roll when it is known.
    func side(roll: Double?) -> Int {
        guard let roll, roll.isFinite else { return turned }
        let turn = roll.truncatingRemainder(dividingBy: 2 * .pi)
        let positive = turn < 0 ? turn + 2 * .pi : turn
        return min(Int(positive / (2 * .pi) * Double(Self.sides)), Self.sides - 1)
    }

    /// How blunt the point is where it touches. A cone is round, so the
    /// neighbouring sides count a little too.
    func bluntness(roll: Double? = nil) -> Double {
        let c = side(roll: roll)
        let n = Self.sides
        return min(0.6 * wear[c] + 0.2 * wear[(c + 1) % n] + 0.2 * wear[(c + n - 1) % n], 1)
    }

    /// The worst side, for showing how the pencil is.
    var worst: Double { wear.max() ?? 0 }

    /// Wears the touching side for `mm` of line drawn at `pressure`.
    mutating func draw(_ mm: Double, pressure: Double, grade: PencilGrade, roll: Double? = nil) {
        guard mm > 0, mm.isFinite else { return }
        let amount = mm / Self.lifeMM(grade) * (0.4 + 1.2 * min(max(pressure, 0), 1))
        let c = side(roll: roll)
        let n = Self.sides
        for (offset, share) in [(0, 0.7), (1, 0.15), (n - 1, 0.15)] {
            let i = (c + offset) % n
            // Each side wears more slowly as it flattens: there is more of it to wear.
            wear[i] = min(wear[i] + amount * share * (1 - 0.5 * wear[i]), 1)
        }
    }

    /// Turns the pencil a sixth in the hand.
    mutating func turn() {
        turned = (turned + 1) % Self.sides
    }

    /// Back to a fine point.
    mutating func sharpen() {
        wear = [Double](repeating: 0, count: Self.sides)
    }
}
