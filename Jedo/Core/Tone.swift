import CoreGraphics
import Foundation

/// The printed pattern of a sheet of screen tone.
enum TonePattern: CaseIterable, Hashable, Sendable {
    case dots10, dots30, dots50
    /// Parallel lines at 45°.
    case lines
    /// Dots growing from light to dark across the sheet.
    case gradation

    var name: String {
        switch self {
        case .dots10: "망점 10%"
        case .dots30: "망점 30%"
        case .dots50: "망점 50%"
        case .lines: "사선"
        case .gradation: "그라데이션"
        }
    }

    /// Distance between dots or lines, in millimetres. About 32 lines to the inch:
    /// coarse enough to read on screen at real size.
    static let pitchMM = 0.8
    /// Width of a printed line, for `lines`.
    static let lineWidthMM = 0.18

    /// Share of the film inked at `x` millimetres across a sheet `width` wide.
    func coverage(atX x: Double, width: Double) -> Double {
        switch self {
        case .dots10: 0.10
        case .dots30: 0.30
        case .dots50: 0.50
        case .lines: Self.lineWidthMM / Self.pitchMM
        case .gradation: 0.05 + 0.55 * min(max(x / max(width, 1), 0), 1)
        }
    }

    /// Radius of a round dot inking `coverage` of its cell.
    static func dotRadius(coverage: Double) -> Double {
        pitchMM * (max(coverage, 0) / .pi).squareRoot()
    }
}

/// What is left of a sheet of tone after the knife: which parts are still
/// on, and where it has been cut. A grid of small cells over the sheet.
///
/// A knife stroke marks the cells it passes through as cut. Peeling at a
/// point lifts the whole piece around it, bounded by cuts and the sheet's
/// edge, the way the waste is lifted off after cutting round a shape.
struct ToneCut: Equatable, Sendable {
    enum Cell: UInt8, Sendable { case gone = 0, kept = 1, kerf = 2 }

    /// Side of a cell in millimetres.
    static let cellMM = 0.25

    let columns: Int
    let rows: Int
    private(set) var cells: [Cell]

    init(widthMM: Double, heightMM: Double) {
        columns = max(Int((widthMM / Self.cellMM).rounded(.up)), 1)
        rows = max(Int((heightMM / Self.cellMM).rounded(.up)), 1)
        cells = Array(repeating: .kept, count: columns * rows)
    }

    func cell(_ column: Int, _ row: Int) -> Cell {
        guard column >= 0, row >= 0, column < columns, row < rows else { return .gone }
        return cells[row * columns + column]
    }

    /// Whether the tone is still on at a point, in millimetres from the sheet's corner.
    func isKept(at p: CGPoint) -> Bool {
        cell(Int((Double(p.x) / Self.cellMM).rounded(.down)), Int((Double(p.y) / Self.cellMM).rounded(.down))) != .gone
    }

    /// Whether any tone is left within `radius` millimetres of a point.
    func hasTone(near p: CGPoint, radius: Double) -> Bool {
        let r = Int((radius / Self.cellMM).rounded(.up))
        let c = Int((Double(p.x) / Self.cellMM).rounded(.down)), w = Int((Double(p.y) / Self.cellMM).rounded(.down))
        for row in (w - r)...(w + r) {
            for column in (c - r)...(c + r) where cell(column, row) != .gone {
                if hypot(Double(column - c), Double(row - w)) <= Double(r) { return true }
            }
        }
        return false
    }

    var keptCount: Int { cells.reduce(0) { $0 + ($1 == .gone ? 0 : 1) } }

    /// Cuts along a straight stretch, in millimetres. The cut never has gaps a
    /// peel could slip through. Returns whether anything changed.
    @discardableResult
    mutating func cut(from a: CGPoint, to b: CGPoint) -> Bool {
        let length = hypot(Double(b.x - a.x), Double(b.y - a.y))
        let steps = max(Int((length / (Self.cellMM * 0.5)).rounded(.up)), 1)
        var changed = false
        var last: (Int, Int)?
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let x = Double(a.x) + Double(b.x - a.x) * t, y = Double(a.y) + Double(b.y - a.y) * t
            let here = (Int((x / Self.cellMM).rounded(.down)), Int((y / Self.cellMM).rounded(.down)))
            changed = mark(here) || changed
            // Two cells meeting only at a corner would let a peel through: close the gap.
            if let (lc, lr) = last, lc != here.0, lr != here.1 {
                changed = mark((here.0, lr)) || changed
            }
            last = here
        }
        return changed
    }

    private mutating func mark(_ at: (Int, Int)) -> Bool {
        let (column, row) = at
        guard column >= 0, row >= 0, column < columns, row < rows else { return false }
        let i = row * columns + column
        guard cells[i] == .kept else { return false }
        cells[i] = .kerf
        return true
    }

    /// Lifts the piece around a point, in millimetres. Refuses when nothing has
    /// been cut away from it (that would be the whole sheet). Returns whether it peeled.
    @discardableResult
    mutating func peel(at p: CGPoint) -> Bool {
        let start = (Int((Double(p.x) / Self.cellMM).rounded(.down)), Int((Double(p.y) / Self.cellMM).rounded(.down)))
        guard cell(start.0, start.1) == .kept else { return false }
        var piece = [Bool](repeating: false, count: cells.count)
        var stack = [start.1 * columns + start.0]
        piece[stack[0]] = true
        var size = 0
        while let i = stack.popLast() {
            size += 1
            let column = i % columns, row = i / columns
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let c = column + dc, r = row + dr
                guard c >= 0, r >= 0, c < columns, r < rows else { continue }
                let j = r * columns + c
                if !piece[j], cells[j] == .kept {
                    piece[j] = true
                    stack.append(j)
                }
            }
        }
        let kept = cells.reduce(0) { $0 + ($1 == .kept ? 1 : 0) }
        guard size < kept else { return false }
        for i in cells.indices where piece[i] { cells[i] = .gone }
        // Cuts left with no tone beside them go with the piece.
        let before = cells
        for i in cells.indices where before[i] == .kerf {
            let column = i % columns, row = i / columns
            let beside = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dc, dr in
                let c = column + dc, r = row + dr
                return c >= 0 && r >= 0 && c < columns && r < rows && before[r * columns + c] == .kept
            }
            if !beside { cells[i] = .gone }
        }
        return true
    }
}
