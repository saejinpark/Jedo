import Foundation

/// How strongly the paper's tooth shows: on blank paper and through graphite.
///
/// Three drafts were compared on a real iPad (strong, subtle, almost none);
/// the almost-none one was chosen, because a stronger grain read as a pattern
/// printed on the paper rather than tooth.
struct GrainStyle: Equatable, Sendable {
    /// Light and shade of the blank paper's tooth.
    var paperRelief: Double
    /// Width of the step between paper that catches graphite and paper that does not.
    /// Wider is gentler: valleys get some graphite instead of none.
    var grainSoftness: Double
    /// Added to every lead's grain threshold. Negative lets graphite reach deeper.
    var grainShift: Double
    /// Grittiness of the lead itself, pixel by pixel.
    var leadNoise: Double

    static let standard = GrainStyle(paperRelief: 0.006, grainSoftness: 0.60, grainShift: -0.40, leadNoise: 0.03)
}
