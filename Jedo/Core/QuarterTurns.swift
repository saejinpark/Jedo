import CoreGraphics
import Foundation

/// A rotation by whole quarter turns, kept exact so the paper is never resampled.
struct QuarterTurns: Equatable, Sendable {
    /// 0...3, clockwise on screen (UIKit's y axis points down).
    let count: Int

    init(_ count: Int) {
        self.count = ((count % 4) + 4) % 4
    }

    /// The nearest quarter turn to a rotation transform, such as the one
    /// UIKit reports when the interface turns with the iPad.
    init(approximating transform: CGAffineTransform) {
        let angle = atan2(Double(transform.b), Double(transform.a))
        self.init(Int((angle / (.pi / 2)).rounded()))
    }

    /// Exactly 0 and ±1 entries, no floating-point residue.
    var transform: CGAffineTransform {
        switch count {
        case 1: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        case 2: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
        case 3: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
        default: .identity
        }
    }

    static func + (lhs: QuarterTurns, rhs: QuarterTurns) -> QuarterTurns { QuarterTurns(lhs.count + rhs.count) }
    static prefix func - (turns: QuarterTurns) -> QuarterTurns { QuarterTurns(-turns.count) }
}
