import Foundation

/// The leads the app offers, as a drafting desk keeps them: hard leads
/// (4H–F) for light construction lines that are left on the sheet, HB and
/// F for finished lines, soft leads for rendering. Hardest first, so
/// `rawValue` grows with softness.
enum PencilGrade: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case h4, h2, h, f, hb, b, b2, b3, b4, b5, b6

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .h4: "4H"
        case .h2: "2H"
        case .h: "H"
        case .f: "F"
        case .hb: "HB"
        case .b: "B"
        case .b2: "2B"
        case .b3: "3B"
        case .b4: "4B"
        case .b5: "5B"
        case .b6: "6B"
        }
    }

    /// 0 for 4H, 1 for 6B.
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
    /// Hard leads burnish and stop taking graphite well before soft ones;
    /// 6B pressed hard and gone over fills the paper black.
    var maxDensity: Double
    /// Paper height (0...1) below which this lead skips the valleys at medium pressure.
    /// Harder leads ride the tooth more, so more paper shows through.
    var grainThreshold: Double
    /// How far the edge of the mark fades, as a fraction of its radius.
    var edgeSoftness: Double

    static let table: [GradeParameters] = [
        //                lineWidthMM  passOpacity  maxDensity  grainThreshold  edgeSoftness
        // Hard leads hold a fine point and ride the tooth: thin, grey lines that
        // stop well short of black however hard they are pressed.
        GradeParameters(lineWidthMM: 0.18, passOpacity: 0.17, maxDensity: 0.34, grainThreshold: 0.36, edgeSoftness: 0.24), // 4H
        GradeParameters(lineWidthMM: 0.21, passOpacity: 0.23, maxDensity: 0.45, grainThreshold: 0.33, edgeSoftness: 0.26), // 2H
        GradeParameters(lineWidthMM: 0.24, passOpacity: 0.29, maxDensity: 0.55, grainThreshold: 0.30, edgeSoftness: 0.27), // H
        GradeParameters(lineWidthMM: 0.27, passOpacity: 0.35, maxDensity: 0.63, grainThreshold: 0.28, edgeSoftness: 0.28), // F
        GradeParameters(lineWidthMM: 0.30, passOpacity: 0.40, maxDensity: 0.70, grainThreshold: 0.26, edgeSoftness: 0.30), // HB
        GradeParameters(lineWidthMM: 0.34, passOpacity: 0.47, maxDensity: 0.76, grainThreshold: 0.23, edgeSoftness: 0.32), // B
        GradeParameters(lineWidthMM: 0.38, passOpacity: 0.54, maxDensity: 0.82, grainThreshold: 0.20, edgeSoftness: 0.34), // 2B
        GradeParameters(lineWidthMM: 0.43, passOpacity: 0.61, maxDensity: 0.87, grainThreshold: 0.17, edgeSoftness: 0.36), // 3B
        GradeParameters(lineWidthMM: 0.49, passOpacity: 0.68, maxDensity: 0.92, grainThreshold: 0.14, edgeSoftness: 0.38), // 4B
        GradeParameters(lineWidthMM: 0.56, passOpacity: 0.75, maxDensity: 0.96, grainThreshold: 0.11, edgeSoftness: 0.40), // 5B
        GradeParameters(lineWidthMM: 0.64, passOpacity: 0.82, maxDensity: 1.00, grainThreshold: 0.08, edgeSoftness: 0.42), // 6B
    ]
}
