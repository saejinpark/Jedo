import Foundation

/// The scale along one edge of the screen: where each millimetre of the
/// paper falls, so tools can be placed by eye and it is clear which part of
/// the paper is in view. Positions are points along the edge from its start.
struct EdgeScale: Equatable, Sendable {
    /// Paper millimetres at the start of the edge (measured from the paper's corner).
    var startMM: Double
    /// Paper millimetres per point along the edge; negative when the paper runs the other way.
    var mmPerPoint: Double
    /// Length of the edge in points.
    var length: Double
    /// How long the paper is along this edge, in millimetres.
    var paperMM: Double

    struct Tick: Equatable, Sendable {
        var at: Double
        var mm: Int
        var weight: GridRulings.Weight
    }

    /// A tick at every whole millimetre in view, in order along the edge: heavier every 5 and 10.
    var ticks: [Tick] {
        guard mmPerPoint != 0, length > 0 else { return [] }
        let end = startMM + mmPerPoint * length
        let low = Int(min(startMM, end).rounded(.up)), high = Int(max(startMM, end).rounded(.down))
        guard low <= high else { return [] }
        let ticks = (low...high).map { mm in
            Tick(at: (Double(mm) - startMM) / mmPerPoint, mm: mm,
                 weight: mm % 10 == 0 ? .bold : mm % 5 == 0 ? .medium : .fine)
        }
        return mmPerPoint > 0 ? ticks : ticks.reversed()
    }

    /// The stretch of the edge the paper lies along, if any of it is in view.
    var paperSpan: ClosedRange<Double>? {
        guard mmPerPoint != 0 else { return nil }
        let a = (0 - startMM) / mmPerPoint, b = (paperMM - startMM) / mmPerPoint
        let lo = max(min(a, b), 0), hi = min(max(a, b), length)
        return lo < hi ? lo...hi : nil
    }
}
