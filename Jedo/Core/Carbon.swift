import CoreGraphics
import Foundation

/// What the carbon is coated with. Carbon paper is sold in navy, black, red,
/// blue and green; the gradients are a fancy of this desk, for stamping.
enum CarbonInk: String, CaseIterable, Hashable, Codable, Sendable {
    case navy, black, red, blue, green
    case rainbow, sunset, sea

    var name: String {
        switch self {
        case .navy: "남색"
        case .black: "검정"
        case .red: "빨강"
        case .blue: "파랑"
        case .green: "초록"
        case .rainbow: "무지개"
        case .sunset: "노을"
        case .sea: "바다"
        }
    }

    var isGradient: Bool { self == .rainbow || self == .sunset || self == .sea }

    /// The palette entry at `t`, 0…1 across the carbon from its left edge.
    func paletteIndex(at t: Double) -> Int {
        let t = min(max(t.isFinite ? t : 0, 0), 1)
        func hue(_ from: Double, _ to: Double) -> Int {
            let degrees = from + (to - from) * t
            let wrapped = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            return CarbonPalette.firstHue + min(Int(wrapped / 360 * Double(CarbonPalette.hueSteps)), CarbonPalette.hueSteps - 1)
        }
        switch self {
        case .navy: return 0
        case .black: return 1
        case .red: return 2
        case .blue: return 3
        case .green: return 4
        case .rainbow: return hue(0, 300)
        case .sunset: return hue(345, 410)
        case .sea: return hue(160, 250)
        }
    }

    /// How it looks laid on the desk, at `t` across.
    func colour(at t: Double) -> (r: Double, g: Double, b: Double) {
        CarbonPalette.colours[paletteIndex(at: t)]
    }
}

/// Every colour a carbon copy can be. Copies keep the colour they were made
/// in: a surface stores `2 × index + density`, so changing or moving the
/// carbon later never repaints what it already copied.
enum CarbonPalette {
    static let firstHue = 5
    static let hueSteps = 64

    static let colours: [(r: Double, g: Double, b: Double)] = {
        var out: [(r: Double, g: Double, b: Double)] = [
            GraphiteShading.carbon,
            (0.06, 0.06, 0.07),
            (0.78, 0.12, 0.12),
            (0.10, 0.28, 0.78),
            (0.08, 0.50, 0.24),
        ]
        for k in 0..<hueSteps { out.append(hsv(Double(k) / Double(hueSteps), 0.85, 0.82)) }
        // Then a cube of colours, for copies coloured by a photo.
        return out + cube
    }()

    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> (r: Double, g: Double, b: Double) {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// Premultiplied pixels per colour and density step.
    static let lookups: [[UInt32]] = colours.map { c in
        (0..<GraphiteShading.levels).map { level in
            let d = Double(level) / Double(GraphiteShading.levels - 1)
            return GraphiteShading.pack(r: c.r * d, g: c.g * d, b: c.b * d, a: d)
        }
    }

    @inline(__always)
    static func split(_ value: Float) -> (index: Int, density: Float) {
        guard value > 0 else { return (0, 0) }
        let index = min(Int(value / 2), colours.count - 1)
        return (index, min(value - Float(2 * index), 1))
    }

    @inline(__always)
    static func join(_ index: Int, _ density: Float) -> Float {
        density <= 0 ? 0 : Float(2 * index) + min(density, 1)
    }

    /// A copy laid over an earlier one: densities build as graphite does,
    /// and the colour is whichever lays more.
    @inline(__always)
    static func lay(base: Float, stroke: Float, index: Int) -> Float {
        let (old, d) = split(base)
        let laid = GraphiteMath.composite(base: d, stroke: stroke, maxDensity: 1)
        return join(stroke >= d ? index : old, laid)
    }

    /// Rubbing a copy out lifts its density, the colour stays what it was.
    @inline(__always)
    static func erase(base: Float, lift: Float) -> Float {
        let (index, d) = split(base)
        return join(index, GraphiteMath.erase(base: d, lift: lift))
    }
}
