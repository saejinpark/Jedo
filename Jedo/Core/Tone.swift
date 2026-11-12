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
    /// How much of the printed ink is left on the film at each cell, 1 as
    /// printed. Scraping with the blade laid flat takes it off.
    private(set) var ink: [Float]

    init(widthMM: Double, heightMM: Double) {
        columns = max(Int((widthMM / Self.cellMM).rounded(.up)), 1)
        rows = max(Int((heightMM / Self.cellMM).rounded(.up)), 1)
        cells = Array(repeating: .kept, count: columns * rows)
        ink = Array(repeating: 1, count: columns * rows)
    }

    /// Whether the print shows at cell `i`: the film is there, and enough ink
    /// is left there. Scraped ink comes off dot by dot, not as a fading wash:
    /// each cell gives way at its own point, so a dot breaks up as it thins.
    func shows(_ i: Int) -> Bool {
        cells[i] == .kept && ink[i] > Self.grit(i)
    }

    /// A fixed roughness for each cell, 0 ..< 1: where the blade catches first.
    static func grit(_ i: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: i) &* 0x9E37_79B1
        h ^= h >> 15
        h = h &* 0x85EB_CA6B
        h ^= h >> 13
        return Float(h & 0xFFFF) / 65536
    }

    /// The blade's flat edge: this wide.
    static let scrapeWidthMM = 3.0
    /// Ink one stroke of the blade lifts at full pressure, in the middle of its edge.
    static let scrapeStrength: Float = 0.35

    /// One sweep of the blade: what it has lifted so far. The blade passes
    /// each spot once per sweep, so within a sweep the firmest scrape counts,
    /// however finely the stroke is sampled. Turning back starts a new sweep.
    struct ScrapePass: Sendable {
        var base: [Float]
        var lift: [Float]
        var heading: (x: Double, y: Double)?

        init(_ tone: ToneCut) {
            base = tone.ink
            lift = Array(repeating: 0, count: tone.ink.count)
        }
    }

    /// Scrapes along a stretch, in millimetres, with the blade laid flat:
    /// each sweep lifts a share of the ink under it, most in the middle of
    /// the edge, so highlights are built up sweep by sweep. Returns whether
    /// any ink came off.
    @discardableResult
    mutating func scrape(from a: CGPoint, to b: CGPoint, pressure: Double, pass: inout ScrapePass) -> Bool {
        let ex = Double(b.x - a.x), ey = Double(b.y - a.y), length2 = ex * ex + ey * ey
        if length2 > 0.04 {
            let length = length2.squareRoot(), dir = (x: ex / length, y: ey / length)
            if let h = pass.heading, h.x * dir.x + h.y * dir.y < -0.3 {
                // Back the other way: a fresh sweep.
                pass.base = ink
                pass.lift = Array(repeating: 0, count: ink.count)
            }
            pass.heading = dir
        }
        let reach = Self.scrapeWidthMM / 2
        let lo = (x: min(Double(a.x), Double(b.x)) - reach, y: min(Double(a.y), Double(b.y)) - reach)
        let hi = (x: max(Double(a.x), Double(b.x)) + reach, y: max(Double(a.y), Double(b.y)) + reach)
        let c0 = max(Int(lo.x / Self.cellMM), 0), c1 = min(Int(hi.x / Self.cellMM), columns - 1)
        let r0 = max(Int(lo.y / Self.cellMM), 0), r1 = min(Int(hi.y / Self.cellMM), rows - 1)
        guard c0 <= c1, r0 <= r1 else { return false }
        let amount = Self.scrapeStrength * Float(0.3 + 0.7 * min(max(pressure, 0), 1))
        var changed = false
        for row in r0...r1 {
            for column in c0...c1 {
                let i = row * columns + column
                guard cells[i] == .kept else { continue }
                let px = (Double(column) + 0.5) * Self.cellMM, py = (Double(row) + 0.5) * Self.cellMM
                let t = length2 > 0 ? min(max(((px - Double(a.x)) * ex + (py - Double(a.y)) * ey) / length2, 0), 1) : 0
                let d = hypot(px - Double(a.x) - ex * t, py - Double(a.y) - ey * t)
                guard d < reach else { continue }
                // Firm in the middle of the edge, light at its ends.
                let lift = amount * Float(1 - (d / reach) * (d / reach))
                guard lift > pass.lift[i] else { continue }
                pass.lift[i] = lift
                let left = max(pass.base[i] - lift, 0)
                if left != ink[i] {
                    ink[i] = left
                    changed = true
                }
            }
        }
        return changed
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
