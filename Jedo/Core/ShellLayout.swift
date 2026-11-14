import CoreGraphics
import Foundation

/// Where the control groups sit, on a grid laid over the whole screen. The
/// grid's square is one control in its card: the sheets button. Every group
/// is a whole number of squares, and sits on whole squares, counted from the
/// screen corner it is nearest, so it keeps its corner when the iPad turns.
///
/// Right-handed, the pencil's choices sit top right, out from under the
/// drawing palm, and what the other hand reaches for (undo, the eraser, the
/// sheets, the tools, the map's stick) sits bottom left. Left-handed is the mirror.
struct ShellLayout: Equatable, Codable, Sendable {
    /// Side of a grid square in points.
    static let unit: CGFloat = 52

    enum Group: String, CaseIterable, Codable, Sendable {
        /// What holds the lead, and the lead's grade (two rows).
        case pencil
        /// The eraser and its kind, the compass, the knife.
        case hand
        /// Rulers, set squares, scale, protractor, pins, templates, curves, the tape measure.
        case desk
        /// The layers panel: what lies on the paper.
        case sheets
        /// Laying sheets: tracing, writing paper, tone, photos, carbon; and the stylus and roller used with carbon.
        case papers
        /// Undo and redo.
        case history
        /// Edge rulers, export, arrangement, new paper.
        case view
        /// The map of the paper and the stick that moves the view.
        case map

        /// Width and height in squares.
        var size: (w: Int, h: Int) {
            switch self {
            case .pencil: (11, 2)
            case .hand: (4, 1)
            case .desk: (11, 1)
            case .sheets: (1, 1)
            case .papers: (7, 1)
            case .history: (2, 1)
            case .view: (4, 1)
            case .map: (3, 5)
            }
        }
    }

    /// Where a group sits: squares in from a corner of the grid.
    struct Spot: Equatable, Codable, Sendable {
        var fromRight: Bool
        var fromBottom: Bool
        var x: Int
        var y: Int
    }

    /// A rectangle of squares, from the grid's top-left.
    struct Cells: Equatable, Sendable {
        var x: Int, y: Int, w: Int, h: Int

        func overlaps(_ o: Cells) -> Bool {
            x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h
        }
    }

    private(set) var spots: [Group: Spot]
    var leftHanded: Bool

    static func standard(leftHanded: Bool) -> ShellLayout {
        let r = !leftHanded
        // Two bands, nothing in between: what the pencil chooses along the top, on its
        // side; what the other hand reaches for along the bottom, from its corner out.
        // The map and its stick stand on that row, under the other hand's thumb.
        return ShellLayout(spots: [
            .pencil: Spot(fromRight: r, fromBottom: false, x: 0, y: 0),
            .view: Spot(fromRight: !r, fromBottom: false, x: 0, y: 0),
            .history: Spot(fromRight: !r, fromBottom: true, x: 0, y: 0),
            .hand: Spot(fromRight: !r, fromBottom: true, x: 2, y: 0),
            .sheets: Spot(fromRight: !r, fromBottom: true, x: 6, y: 0),
            .desk: Spot(fromRight: !r, fromBottom: true, x: 7, y: 0),
            .map: Spot(fromRight: !r, fromBottom: true, x: 0, y: 1),
            .papers: Spot(fromRight: !r, fromBottom: true, x: 3, y: 1),
        ], leftHanded: leftHanded)
    }

    /// Where each group lands on a grid `columns` by `rows`, with overlaps
    /// (after turning the iPad, say) moved to the nearest free squares. The
    /// map is left out when `withMap` is false (paper fitted to the screen).
    func cells(columns: Int, rows: Int, withMap: Bool = true) -> [Group: Cells] {
        var out: [Group: Cells] = [:]
        let order: [Group] = [.map, .view, .pencil, .history, .hand, .sheets, .desk, .papers]
        for group in order where withMap || group != .map {
            guard let spot = spots[group] else { continue }
            let (w, h) = group.size
            var want = Self.cells(spot, w: w, h: h, columns: columns, rows: rows)
            want.x = min(max(want.x, 0), max(columns - w, 0))
            want.y = min(max(want.y, 0), max(rows - h, 0))
            out[group] = Self.nearestFree(want, avoiding: Array(out.values), columns: columns, rows: rows)
        }
        return out
    }

    static func cells(_ spot: Spot, w: Int, h: Int, columns: Int, rows: Int) -> Cells {
        Cells(x: spot.fromRight ? columns - spot.x - w : spot.x, y: spot.fromBottom ? rows - spot.y - h : spot.y, w: w, h: h)
    }

    /// The closest place to `want` that overlaps none of `taken`, or `want` if there is none.
    static func nearestFree(_ want: Cells, avoiding taken: [Cells], columns: Int, rows: Int) -> Cells {
        guard taken.contains(where: want.overlaps) else { return want }
        var best: (Cells, Int)?
        for y in 0...max(rows - want.h, 0) {
            for x in 0...max(columns - want.w, 0) {
                let c = Cells(x: x, y: y, w: want.w, h: want.h)
                guard !taken.contains(where: c.overlaps) else { continue }
                let d = abs(x - want.x) + abs(y - want.y)
                if best == nil || d < best!.1 { best = (c, d) }
            }
        }
        return best?.0 ?? want
    }

    /// Puts a group where it was dropped, counted from the corner it is
    /// nearest. Refused (returns false) where another group already is.
    @discardableResult
    mutating func place(_ group: Group, at cells: Cells, columns: Int, rows: Int, withMap: Bool = true) -> Bool {
        let others = self.cells(columns: columns, rows: rows, withMap: withMap).filter { $0.key != group }.map(\.value)
        guard cells.x >= 0, cells.y >= 0, cells.x + cells.w <= columns, cells.y + cells.h <= rows,
              !others.contains(where: cells.overlaps) else { return false }
        let fromRight = cells.x + cells.w / 2 > columns / 2
        let fromBottom = cells.y + cells.h / 2 > rows / 2
        spots[group] = Spot(fromRight: fromRight, fromBottom: fromBottom,
                            x: fromRight ? columns - cells.x - cells.w : cells.x,
                            y: fromBottom ? rows - cells.y - cells.h : cells.y)
        return true
    }

    /// The same arrangement for the other hand.
    var mirrored: ShellLayout {
        ShellLayout(spots: spots.mapValues { Spot(fromRight: !$0.fromRight, fromBottom: $0.fromBottom, x: $0.x, y: $0.y) },
                    leftHanded: !leftHanded)
    }

    var isComplete: Bool { Set(spots.keys) == Set(Group.allCases) }

    // MARK: Saving

    var encoded: String {
        (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? ""
    }

    /// A saved arrangement, or nil if it is missing or doesn't place every group.
    init?(encoded: String) {
        guard let layout = try? JSONDecoder().decode(ShellLayout.self, from: Data(encoded.utf8)), layout.isComplete else { return nil }
        self = layout
    }

    private init(spots: [Group: Spot], leftHanded: Bool) {
        self.spots = spots
        self.leftHanded = leftHanded
    }
}
