import CoreGraphics
import Foundation

/// What the carbon is coated with. Carbon paper is sold in navy, black, red,
/// blue and green; the gradients are a fancy of this desk, for stamping.
enum CarbonInk: String, CaseIterable, Hashable, Codable, Sendable {
    case navy, black, red, blue, green
    case rainbow, sunset, sea
    /// Coated in a cloth's print, for laying a fabric into a fashion drawing.
    case stripe, gingham, dots, tartan, houndstooth

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
        case .stripe: "줄무늬"
        case .gingham: "깅엄 체크"
        case .dots: "물방울"
        case .tartan: "타탄 체크"
        case .houndstooth: "하운드투스"
        }
    }

    var isGradient: Bool { self == .rainbow || self == .sunset || self == .sea }
    var isPattern: Bool { [.stripe, .gingham, .dots, .tartan, .houndstooth].contains(self) }
    /// Whether the coating is one colour all over.
    var isPlain: Bool { !isGradient && !isPattern }

    /// The colour of a cloth print at a point of the carbon, in millimetres from its top-left corner.
    func printColour(atMM x: Double, _ y: Double) -> (r: Double, g: Double, b: Double) {
        func wrap(_ v: Double, _ period: Double) -> Double { let m = v.truncatingRemainder(dividingBy: period); return m < 0 ? m + period : m }
        let white = (r: 1.0, g: 1.0, b: 0.93), navy = (r: 0.11, g: 0.16, b: 0.36)
        switch self {
        case .stripe:
            return wrap(x, 8) < 4 ? navy : white
        case .gingham:
            let a = wrap(x, 10) < 5, b = wrap(y, 10) < 5
            return a && b ? (0.14, 0.32, 0.72) : a || b ? (0.56, 0.69, 0.90) : white
        case .dots:
            // Rows of dots, every other row set half a step along.
            let row = (y / 8).rounded(.down)
            let dx = wrap(x + (Int(row) % 2 == 0 ? 0 : 5), 10) - 5, dy = wrap(y, 8) - 4
            return dx * dx + dy * dy < 2.4 * 2.4 ? white : (0.80, 0.16, 0.20)
        case .tartan:
            // Each way: red ground, a broad green band, a navy stripe, a yellow thread. Where two cross they mix, as weaving does.
            func thread(_ v: Double) -> (r: Double, g: Double, b: Double) {
                let t = wrap(v, 40)
                return t < 12 ? (0.08, 0.36, 0.22) : (18..<22).contains(t) ? navy : (30..<31.2).contains(t) ? (0.93, 0.78, 0.25) : (0.74, 0.12, 0.14)
            }
            let a = thread(x), b = thread(y)
            return ((a.r + b.r) / 2, (a.g + b.g) / 2, (a.b + b.b) / 2)
        case .houndstooth:
            // Four dark threads, four light, both ways, in a two-over-two twill.
            let i = Int((x / 1.5).rounded(.down)), j = Int((y / 1.5).rounded(.down))
            let dark = { (k: Int) in ((k % 8) + 8) % 8 < 4 }
            let warpOver = (((i + j) % 4) + 4) % 4 < 2
            return (warpOver ? dark(i) : dark(j)) ? (0.07, 0.07, 0.08) : white
        default:
            return colour(at: 0)
        }
    }

    /// The palette entry a cloth print presses at a point of the carbon.
    func printIndex(atMM x: Double, _ y: Double) -> Int { CarbonPalette.cubeIndex(printColour(atMM: x, y)) }

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
        case .stripe, .gingham, .dots, .tartan, .houndstooth: return printIndex(atMM: t * 40, 2)
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

    /// Each colour as 0…255 channels, for packing pixels fast.
    private static let bytes: [(r: Float, g: Float, b: Float)] = colours.map { (Float($0.r) * 255, Float($0.g) * 255, Float($0.b) * 255) }

    /// A premultiplied pixel of colour `index` at `density`.
    @inline(__always)
    static func pixel(_ index: Int, _ density: Float) -> UInt32 {
        let c = bytes[index], a = min(max(density, 0), 1)
        return UInt32(a * 255 + 0.5) << 24 | UInt32(c.r * a + 0.5) << 16 | UInt32(c.g * a + 0.5) << 8 | UInt32(c.b * a + 0.5)
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

    /// A copy laid over an earlier one: densities build as graphite does, and
    /// what is pressed later lies on top, so it takes the colour. Only a faint
    /// fringe (the soft edge of a line) leaves the colour under it showing.
    static let coversAbove: Float = 0.3

    @inline(__always)
    static func lay(base: Float, stroke: Float, index: Int) -> Float {
        let (old, d) = split(base)
        let laid = GraphiteMath.composite(base: d, stroke: stroke, maxDensity: 1)
        return join(stroke >= coversAbove || stroke >= d ? index : old, laid)
    }

    /// Rubbing a copy out lifts its density, the colour stays what it was.
    @inline(__always)
    static func erase(base: Float, lift: Float) -> Float {
        let (index, d) = split(base)
        return join(index, GraphiteMath.erase(base: d, lift: lift))
    }
}
