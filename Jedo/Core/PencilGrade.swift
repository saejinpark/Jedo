import Foundation

/// The seven leads the app offers. Hardest first, so `rawValue` grows with softness.
enum PencilGrade: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case hb, b, b2, b3, b4, b5, b6

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hb: "HB"
        case .b: "B"
        case .b2: "2B"
        case .b3: "3B"
        case .b4: "4B"
        case .b5: "5B"
        case .b6: "6B"
        }
    }

    /// 0 for HB, 1 for 6B.
    var softness: Double { Double(rawValue) / Double(Self.allCases.count - 1) }

    var parameters: GradeParameters { GradeParameters.table[rawValue] }

    static func < (lhs: PencilGrade, rhs: PencilGrade) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How one lead behaves on paper. Every number here is a hand-feel knob:
/// they were set by eye on rendered specimens and are expected to change
/// after trying them on a real iPad.
struct GradeParameters: Equatable, Sendable {
    /// Width of the line a freshly sharpened point leaves at medium pressure, in millimetres.
    /// Softer leads wear blunt faster, so their lines are broader.
    var lineWidthMM: Double
    /// Graphite one pass leaves at medium pressure, before paper grain (0...1).
    var passOpacity: Double
    /// The darkest this lead can make the paper, however often you go over it.
    /// Hard leads burnish and stop taking graphite well before soft ones.
    var maxDensity: Double
    /// Paper height (0...1) below which this lead skips the valleys at medium pressure.
    /// Harder leads ride the tooth more, so more paper shows through.
    var grainThreshold: Double
    /// How far the edge of the mark fades, as a fraction of its radius.
    var edgeSoftness: Double

    static let table: [GradeParameters] = [
        //                lineWidthMM  passOpacity  maxDensity  grainThreshold  edgeSoftness
        GradeParameters(lineWidthMM: 0.30, passOpacity: 0.40, maxDensity: 0.60, grainThreshold: 0.30, edgeSoftness: 0.30), // HB
        GradeParameters(lineWidthMM: 0.34, passOpacity: 0.47, maxDensity: 0.67, grainThreshold: 0.27, edgeSoftness: 0.32), // B
        GradeParameters(lineWidthMM: 0.38, passOpacity: 0.54, maxDensity: 0.73, grainThreshold: 0.24, edgeSoftness: 0.34), // 2B
        GradeParameters(lineWidthMM: 0.43, passOpacity: 0.61, maxDensity: 0.79, grainThreshold: 0.21, edgeSoftness: 0.36), // 3B
        GradeParameters(lineWidthMM: 0.49, passOpacity: 0.68, maxDensity: 0.84, grainThreshold: 0.18, edgeSoftness: 0.38), // 4B
        GradeParameters(lineWidthMM: 0.56, passOpacity: 0.75, maxDensity: 0.89, grainThreshold: 0.15, edgeSoftness: 0.40), // 5B
        GradeParameters(lineWidthMM: 0.64, passOpacity: 0.82, maxDensity: 0.93, grainThreshold: 0.12, edgeSoftness: 0.42), // 6B
    ]
}
