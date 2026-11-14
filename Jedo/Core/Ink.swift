import CoreGraphics
import Foundation

/// Line widths of a technical pen set (ISO 128: each about √2 times the last).
enum PenWidth: CaseIterable, Hashable, Sendable {
    case w013, w018, w025, w035, w05, w07, w10

    var mm: Double {
        switch self {
        case .w013: 0.13
        case .w018: 0.18
        case .w025: 0.25
        case .w035: 0.35
        case .w05: 0.5
        case .w07: 0.7
        case .w10: 1.0
        }
    }

    var label: String {
        switch self {
        case .w013: "0.13"
        case .w018: "0.18"
        case .w025: "0.25"
        case .w035: "0.35"
        case .w05: "0.5"
        case .w07: "0.7"
        case .w10: "1.0"
        }
    }
}

/// Dip-pen nibs for comic inking. A split steel nib spreads under pressure,
/// so the line swells and thins with the hand.
enum Nib: CaseIterable, Hashable, Sendable {
    /// The G-pen: soft and springy, from a hairline to a bold stroke.
    case gPen
    /// The maru (mapping) pen: hard and fine, for detail and hatching.
    case maru

    var name: String {
        switch self {
        case .gPen: "G펜"
        case .maru: "마루펜"
        }
    }

    var label: String {
        switch self {
        case .gPen: "G"
        case .maru: "마루"
        }
    }

    /// Width at the lightest touch and at full pressure, in millimetres.
    var widthRangeMM: ClosedRange<Double> {
        switch self {
        case .gPen: 0.08...1.3
        case .maru: 0.05...0.45
        }
    }

    /// How late the nib opens: above 1 it stays fine until pressed in earnest.
    var opening: Double {
        switch self {
        case .gPen: 1.6
        case .maru: 1.3
        }
    }
}

/// How the hand's pressure sets an ink line. Ink is laid solid: no tooth
/// shows through, and going over it again changes nothing.
struct InkDynamics: Sendable {
    enum Pen: Hashable, Sendable {
        case technical(PenWidth)
        case dip(Nib)
    }

    let pen: Pen
    let pixelsPerMillimeter: Double

    /// Width of the line, in millimetres, at `pressure` (0...1).
    static func widthMM(_ pen: Pen, pressure: Double) -> Double {
        switch pen {
        case .technical(let width):
            // A tube of fixed bore: the hand's weight doesn't change the line.
            return width.mm
        case .dip(let nib):
            let p = min(max(pressure.isFinite ? pressure : 0, 0), 1)
            let range = nib.widthRangeMM
            return range.lowerBound + (range.upperBound - range.lowerBound) * pow(p, nib.opening)
        }
    }

    func radius(for sample: StrokeSample) -> Double {
        max(Self.widthMM(pen, pressure: sample.pressure) / 2 * pixelsPerMillimeter, 0.6)
    }

    func spacing(for sample: StrokeSample) -> Double {
        max(radius(for: sample) * 0.25, 0.4)
    }
}

/// Lays a round dab of ink: solid, with an antialiased edge.
enum InkRasterizer {
    static func bounds(center: CGPoint, radius: Double) -> PixelRect {
        let r = radius + 1.5
        return PixelRect(minX: Int((Double(center.x) - r).rounded(.down)), minY: Int((Double(center.y) - r).rounded(.down)),
                         maxX: Int((Double(center.x) + r).rounded(.up)), maxY: Int((Double(center.y) + r).rounded(.up)))
    }

    /// `strength` scales the dab: the depth of a stylus press.
    static func stamp(center: CGPoint, radius: Double, into raster: inout GraphiteRaster, strength: Float = 1) -> PixelRect {
        let area = bounds(center: center, radius: radius).intersection(raster.bounds)
        guard !area.isEmpty else { return .empty }
        let cx = Float(center.x), cy = Float(center.y), r = Float(radius)
        let size = GraphiteRaster.tileSize
        for coord in raster.tileCoords(overlapping: area) {
            let tileRect = raster.rect(of: coord).intersection(area)
            let originX = coord.x * size, originY = coord.y * size
            raster.withMutableTile(coord) { buffer in
                for py in tileRect.minY..<tileRect.maxY {
                    let dy = Float(py) + 0.5 - cy
                    let row = (py - originY) * size - originX
                    for px in tileRect.minX..<tileRect.maxX {
                        let dx = Float(px) + 0.5 - cx
                        // A one-pixel ramp at the edge.
                        let coverage = min(max(r + 0.5 - (dx * dx + dy * dy).squareRoot(), 0), 1) * strength
                        let index = row + px
                        if coverage > buffer[index] { buffer[index] = coverage }
                    }
                }
            }
        }
        return area
    }
}

/// Ink shares the graphite raster: values up to 1 are graphite density, and
/// above 1 the excess is how much of the spot ink covers. Ink sits on top of
/// graphite, so where it lands the graphite under it no longer counts.
extension GraphiteMath {
    /// How much of a spot ink covers.
    @inline(__always)
    static func inkCoverage(_ value: Float) -> Float { max(value - 1, 0) }

    /// Ink of `coverage` laid over `base`. A faint antialiased edge does not
    /// lighten graphite darker than itself.
    @inline(__always)
    static func ink(base: Float, coverage: Float) -> Float {
        guard coverage > 0 else { return base }
        let held = inkCoverage(base)
        if held == 0, base >= coverage { return base }
        return 1 + max(held, coverage)
    }

    /// An eraser over graphite or ink: graphite gives up `lift` of itself;
    /// ink gives up only `inkLift` of that, since ink sits in the paper.
    /// A dent stays a dent.
    @inline(__always)
    static func erase(base: Float, lift: Float, inkLift: Float, dentLift: Float = 0) -> Float {
        if base < 0 {
            // Rubbing flattens the groove back into the paper, a little each pass.
            let left = base * (1 - lift * dentLift)
            return left > -0.03 ? 0 : left
        }
        guard base > 1 else { return erase(base: base, lift: lift) }
        let left = inkCoverage(base) * (1 - lift * inkLift)
        return left > 0.02 ? 1 + left : 0
    }
}

/// A dent pressed into the paper with the embossing stylus: the raster holds
/// it below zero, as deep as it went. Graphite rubbed over the paper can't
/// reach into it, so it stays white: the white-line technique. Ink runs into it.
extension GraphiteMath {
    @inline(__always)
    static func dent(base: Float, depth: Float) -> Float {
        // Pressed over a mark already made, the mark stays.
        guard depth > 0, base <= 0.02 else { return base }
        return min(base, -depth)
    }
}

/// The embossing stylus (누름 막대): a smooth steel ball on a handle, no lead.
struct StylusDynamics: Sendable {
    let pixelsPerMillimeter: Double

    /// The ball: a fine 0.8 mm tip.
    static let ballMM = 0.8

    func radius(for sample: StrokeSample) -> Double {
        let p = min(max(sample.pressure.isFinite ? sample.pressure : 0, 0), 1)
        return max(Self.ballMM / 2 * (0.7 + 0.5 * p) * pixelsPerMillimeter, 0.8)
    }

    /// How deep a press goes, 0...1.
    func depth(for sample: StrokeSample) -> Float {
        let p = min(max(sample.pressure.isFinite ? sample.pressure : 0, 0), 1)
        return Float(min(0.25 + 0.9 * p, 1))
    }

    func spacing(for sample: StrokeSample) -> Double { max(radius(for: sample) * 0.3, 0.4) }
}

/// The brayer: 30 mm of rubber. It lays down only what is pressed through carbon.
struct RollerDynamics: Sendable {
    let pixelsPerMillimeter: Double
    static let widthMM = 30.0

    var radius: Double { Self.widthMM / 2 * pixelsPerMillimeter }
    var spacing: Double { max(radius * 0.12, 0.5) }

    /// Rolled lightly the carbon gives a little; leaned on, nearly all.
    func strength(for sample: StrokeSample) -> Float {
        let p = min(max(sample.pressure.isFinite ? sample.pressure : 0, 0), 1)
        return Float(0.3 + 0.65 * p)
    }
}

extension GraphiteShading {
    /// A dent catches a little shadow on its far wall: faint, but there to see.
    static let dentLookup: [UInt32] = (0..<levels).map { level in
        let d = Double(level) / Double(levels - 1)
        let a = 0.11 * d
        return pack(r: 0.45 * a, g: 0.45 * a, b: 0.47 * a, a: a)
    }

    /// India ink: dense and slightly warmer than graphite's sheen.
    static let ink: (r: Double, g: Double, b: Double) = (0.03, 0.03, 0.035)

    /// Premultiplied ink at each coverage step.
    static let inkLookup: [UInt32] = (0..<levels).map { level in
        let c = Double(level) / Double(levels - 1)
        return pack(r: ink.r * c, g: ink.g * c, b: ink.b * c, a: c)
    }
}
