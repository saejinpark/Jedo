import Foundation

/// The mark one touch of the lead leaves: an ellipse of graphite.
struct DabShape: Equatable, Sendable {
    /// Radius along `angle`, in pixels.
    var radiusAlong: Double
    /// Radius across `angle`, in pixels.
    var radiusAcross: Double
    /// Radians: the direction the pencil leans, which is where a tilted lead's
    /// contact patch stretches.
    var angle: Double
    /// Graphite laid on fully caught paper (0...1).
    var opacity: Double
    /// Paper height below which graphite misses (0...1).
    var grainThreshold: Double
    /// Edge fade as a fraction of the radius.
    var edgeSoftness: Double
    /// Width of the grain threshold's soft step, in paper-height units.
    var grainSoftness: Double = GrainStyle.standard.grainSoftness
    /// Grittiness of the lead itself.
    var leadNoise: Double = GrainStyle.standard.leadNoise

    var minRadius: Double { min(radiusAlong, radiusAcross) }
    var maxRadius: Double { max(radiusAlong, radiusAcross) }
}

/// The thicknesses of drafting mechanical-pencil lead.
enum LeadSize: CaseIterable, Hashable, Sendable {
    case mm03, mm05, mm07, mm09

    var diameterMM: Double {
        switch self {
        case .mm03: 0.3
        case .mm05: 0.5
        case .mm07: 0.7
        case .mm09: 0.9
        }
    }

    var label: String {
        switch self {
        case .mm03: "0.3"
        case .mm05: "0.5"
        case .mm07: "0.7"
        case .mm09: "0.9"
        }
    }
}

/// What holds the lead. Both keep their point: Apple Pencil's tip never
/// wears, so neither does the app's (see DESIGN.md, principle 4).
enum Instrument: Hashable, Sendable {
    /// A wood-cased pencil: the line's width comes with the grade, and laid
    /// over on its side it shades a broad patch.
    case wood
    /// A drafting mechanical pencil: the lead's diameter sets the line, and
    /// its sleeve keeps it from being laid flat.
    case mechanical(LeadSize)

    var name: String {
        switch self {
        case .wood: "연필"
        case .mechanical(let size): "제도 샤프 \(size.label)mm"
        }
    }
}

/// How pressure and tilt change the mark of one lead.
struct PencilDynamics: Sendable {
    var grade: PencilGrade
    var pixelsPerMillimeter: Double
    var instrument: Instrument = .wood
    var style: GrainStyle = .standard

    // MARK: Hand-feel knobs

    /// A held pencil sits around 50–60° most of the time. Above this the point
    /// still writes with its tip, so the line does not change.
    static let tiltStartsBelow = 50.0 * .pi / 180
    /// At or below this the lead is on its side and the patch is as wide as it gets.
    static let fullSideBelow = 15.0 * .pi / 180
    /// How much longer / wider the patch gets lying on its side.
    static let sideStretchAlong = 8.0
    static let sideStretchAcross = 3.0
    /// The same pressure spread over a larger patch lays less graphite per spot.
    static let sideOpacityDrop = 0.9
    /// On its side the lead skims the tooth, so more paper shows through.
    static let sideGrainLift = 0.12
    /// How far pressure moves the grain threshold either side of medium.
    /// Pressing hard flattens the tooth so graphite fills the valleys.
    static let pressureGrain = 0.6
    /// Pressing harder squashes the point a little wider.
    static let pressureWidening = 0.5
    /// A mechanical pencil's lead hardly squashes, and its sleeve stops it
    /// going over: tilting only stretches the mark this much.
    static let mechanicalPressureWidening = 0.15
    static let mechanicalStretchAlong = 1.4
    static let mechanicalStretchAcross = 1.1
    static let mechanicalOpacityDrop = 0.15
    /// Softer leads smear a little past the lead's own diameter.
    static let mechanicalSoftSpread = 0.12

    /// The width a lead leaves at medium pressure, held upright.
    static func lineWidthMM(_ grade: PencilGrade, _ instrument: Instrument) -> Double {
        switch instrument {
        case .wood: grade.parameters.lineWidthMM
        case .mechanical(let size): size.diameterMM * (1 + mechanicalSoftSpread * grade.softness)
        }
    }

    /// Never thinner than this, so the lightest touch still shows.
    static let minimumRadiusPixels = 0.6

    /// 0 while writing with the tip, 1 with the lead flat on its side.
    func sideAmount(altitude: Double) -> Double {
        let a = min(max(altitude, 0), .pi / 2)
        return smoothstep(Self.tiltStartsBelow, Self.fullSideBelow, a)
    }

    func shape(for sample: StrokeSample) -> DabShape {
        let p = min(max(sample.pressure.isFinite ? sample.pressure : 0, 0), 1)
        let params = grade.parameters
        let side = sideAmount(altitude: sample.altitude.isFinite ? sample.altitude : .pi / 2)
        let mechanical = if case .mechanical = instrument { true } else { false }
        let widening = mechanical ? Self.mechanicalPressureWidening : Self.pressureWidening
        let stretchAlong = mechanical ? Self.mechanicalStretchAlong : Self.sideStretchAlong
        let stretchAcross = mechanical ? Self.mechanicalStretchAcross : Self.sideStretchAcross
        let opacityDrop = mechanical ? Self.mechanicalOpacityDrop : Self.sideOpacityDrop
        let grainLift = mechanical ? Self.sideGrainLift * 0.25 : Self.sideGrainLift

        let tipRadius = max(Self.lineWidthMM(grade, instrument) / 2 * pixelsPerMillimeter
                            * (1 - widening / 2 + widening * p),
                            Self.minimumRadiusPixels)

        // Light touches lay little graphite; medium pressure is the grade's own value.
        let pressureResponse = 0.15 + 1.7 * pow(p, 0.9)
        let opacity = min(params.passOpacity * pressureResponse / (1 + opacityDrop * side), 1)

        // Pressing fills the valleys of the paper; a light hand only touches the peaks.
        let threshold = params.grainThreshold + style.grainShift
            + Self.pressureGrain * (0.5 - p) + grainLift * side

        return DabShape(
            radiusAlong: tipRadius * (1 + (stretchAlong - 1) * side),
            radiusAcross: tipRadius * (1 + (stretchAcross - 1) * side),
            angle: sample.azimuth.isFinite ? sample.azimuth : 0,
            opacity: opacity,
            grainThreshold: min(max(threshold, -0.6), 0.95),
            edgeSoftness: min(params.edgeSoftness + (mechanical ? 0.08 : 0.3) * side, 0.9),
            grainSoftness: style.grainSoftness,
            leadNoise: style.leadNoise
        )
    }

    /// Distance between dabs, in pixels. A quarter of the narrow diameter
    /// keeps the edge free of scallops.
    func spacing(for shape: DabShape) -> Double {
        max(shape.minRadius * 0.5, 0.35)
    }
}

@inline(__always)
func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    guard edge0 != edge1 else { return x < edge0 ? 0 : 1 }
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
