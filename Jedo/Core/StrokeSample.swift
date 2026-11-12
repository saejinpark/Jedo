import CoreGraphics

/// One reading of the pencil, already converted to canvas pixels and normalised.
struct StrokeSample: Equatable, Sendable {
    /// Position in canvas pixels.
    var location: CGPoint
    /// 0 (barely touching) ... 1 (pressing hard). See `PressureCurve`.
    var pressure: Double
    /// Radians. π/2 is the pencil standing upright, 0 is lying flat.
    var altitude: Double
    /// Radians, in the canvas plane: the direction the pencil leans.
    var azimuth: Double
    /// The lead starts going over its own line again here, so what follows
    /// darkens what the stroke already laid, as a second pass would.
    var beginsPass = false
    /// How worn the side of the lead touching the paper is: 0 freshly
    /// sharpened, 1 worn flat. See `LeadPoint`.
    var bluntness: Double = 0

    init(location: CGPoint, pressure: Double = 0.5, altitude: Double = .pi / 2, azimuth: Double = 0, bluntness: Double = 0) {
        self.location = location
        self.pressure = pressure
        self.altitude = altitude
        self.azimuth = azimuth
        self.bluntness = bluntness
    }

    /// Linear blend; the azimuth takes the short way round. Never begins a pass.
    static func interpolate(_ a: StrokeSample, _ b: StrokeSample, _ t: Double) -> StrokeSample {
        StrokeSample(
            location: CGPoint(x: a.location.x + (b.location.x - a.location.x) * t,
                              y: a.location.y + (b.location.y - a.location.y) * t),
            pressure: a.pressure + (b.pressure - a.pressure) * t,
            altitude: a.altitude + (b.altitude - a.altitude) * t,
            azimuth: interpolateAngle(a.azimuth, b.azimuth, t),
            bluntness: a.bluntness + (b.bluntness - a.bluntness) * t
        )
    }

    static func interpolateAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var delta = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return a + delta * t
    }
}

/// Turns Apple Pencil force into the 0...1 pressure the dynamics expect.
enum PressureCurve {
    /// Fraction of `maximumPossibleForce` that counts as pressing as hard as anyone draws.
    /// Apple Pencil reports a maximum around 4.17, while firm drafting pressure sits near 2.
    static let fullScale = 0.5
    /// Below 1 lifts light pressure, so a relaxed hand still gets a usable line.
    static let gamma = 0.85

    static func pressure(force: Double, maximumPossibleForce: Double) -> Double {
        guard maximumPossibleForce > 0, force.isFinite else { return 0 }
        let linear = min(max(force / (maximumPossibleForce * fullScale), 0), 1)
        return pow(linear, gamma)
    }
}
