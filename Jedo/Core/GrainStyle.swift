import Foundation

/// How strongly the paper's tooth shows: on blank paper and through graphite.
/// These are drafts to compare on a real iPad; the app lets you switch between them.
struct GrainStyle: Equatable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    /// Light and shade of the blank paper's tooth.
    var paperRelief: Double
    /// Width of the step between paper that catches graphite and paper that does not.
    /// Wider is gentler: valleys get some graphite instead of none.
    var grainSoftness: Double
    /// Added to every lead's grain threshold. Negative lets graphite reach deeper.
    var grainShift: Double
    /// Grittiness of the lead itself, pixel by pixel.
    var leadNoise: Double

    /// The first version, which looked forced on a real iPad.
    static let strong = GrainStyle(name: "강하게", paperRelief: 0.045, grainSoftness: 0.24, grainShift: 0, leadNoise: 0.12)
    static let subtle = GrainStyle(name: "은은하게", paperRelief: 0.018, grainSoftness: 0.45, grainShift: -0.10, leadNoise: 0.05)
    static let faint = GrainStyle(name: "거의 없음", paperRelief: 0.006, grainSoftness: 0.60, grainShift: -0.40, leadNoise: 0.03)

    static let all: [GrainStyle] = [.strong, .subtle, .faint]
    static let `default` = subtle
}
