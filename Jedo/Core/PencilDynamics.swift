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

/// How pressure and tilt change the mark of one lead.
struct PencilDynamics: Sendable {
    var grade: PencilGrade
    var pixelsPerMillimeter: Double
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
    /// A lead worn flat lays a line this much wider than a sharp one…
    static let bluntWidening = 1.4
    /// …and spreads the same graphite thinner.
    static let bluntOpacityDrop = 0.2
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

        let blunt = min(max(sample.bluntness.isFinite ? sample.bluntness : 0, 0), 1)
        let tipRadius = max(params.lineWidthMM / 2 * pixelsPerMillimeter
                            * (1 - Self.pressureWidening / 2 + Self.pressureWidening * p)
                            * (1 + Self.bluntWidening * blunt),
                            Self.minimumRadiusPixels)

        // Light touches lay little graphite; medium pressure is the grade's own value.
        let pressureResponse = 0.15 + 1.7 * pow(p, 0.9)
        let opacity = min(params.passOpacity * pressureResponse / (1 + Self.sideOpacityDrop * side)
                          * (1 - Self.bluntOpacityDrop * blunt), 1)

        // Pressing fills the valleys of the paper; a light hand only touches the peaks.
        let threshold = params.grainThreshold + style.grainShift
            + Self.pressureGrain * (0.5 - p) + Self.sideGrainLift * side

        return DabShape(
            radiusAlong: tipRadius * (1 + (Self.sideStretchAlong - 1) * side),
            radiusAcross: tipRadius * (1 + (Self.sideStretchAcross - 1) * side),
            angle: sample.azimuth.isFinite ? sample.azimuth : 0,
            opacity: opacity,
            grainThreshold: min(max(threshold, -0.6), 0.95),
            edgeSoftness: min(params.edgeSoftness + 0.3 * side, 0.9),
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
