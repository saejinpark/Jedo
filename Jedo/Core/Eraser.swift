import CoreGraphics
import Foundation

/// How a rub of the eraser takes graphite off. A finger rubs with it; the
/// pencil keeps drawing. (Turning the pencil into the eraser was the other
/// draft compared on the iPad; rubbing with a finger was chosen.)
struct EraserDynamics: Sendable {
    let pixelsPerMillimeter: Double

    /// The worn corner of a drafting eraser.
    static let widthMM = 5.0
    /// Fraction of the graphite one light rub lifts, and how much more a firm one does.
    static let baseStrength = 0.25
    static let pressureStrength = 0.45
    /// Graphite in the paper's valleys is harder to reach than on its peaks.
    static let valleyResistance = 0.3

    var radius: Double { Self.widthMM / 2 * pixelsPerMillimeter }
    var spacing: Double { max(radius * 0.2, 0.5) }

    func strength(for sample: StrokeSample) -> Double {
        min(Self.baseStrength + Self.pressureStrength * sample.pressure, 0.95)
    }
}

/// Lays one dab of an eraser rub into a stroke buffer: how much of the
/// graphite to take off at each pixel. Within a pass the strongest rub wins.
enum EraserRasterizer {
    /// Pixels a dab can touch.
    static func bounds(center: CGPoint, radius: Double) -> PixelRect {
        guard center.x.isFinite, center.y.isFinite else { return .empty }
        let reach = radius + 1
        return PixelRect(minX: Int((Double(center.x) - reach).rounded(.down)), minY: Int((Double(center.y) - reach).rounded(.down)),
                         maxX: Int((Double(center.x) + reach).rounded(.up)) + 1, maxY: Int((Double(center.y) + reach).rounded(.up)) + 1)
    }

    @discardableResult
    static func stamp(center: CGPoint, radius: Double, strength: Double, into raster: inout GraphiteRaster,
                      paper: PaperTexture) -> PixelRect {
        guard center.x.isFinite, center.y.isFinite, radius > 0, strength > 0 else { return .empty }
        let area = bounds(center: center, radius: radius).intersection(raster.bounds)
        guard !area.isEmpty else { return .empty }

        let cx = Float(center.x), cy = Float(center.y)
        let r = Float(radius)
        let soft = max(r * 0.3, 1)
        let amount = Float(strength)
        let resistance = Float(EraserDynamics.valleyResistance)
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
                        let d = (dx * dx + dy * dy).squareRoot()
                        if d >= r { continue }
                        let coverage = 1 - smoothstepF(r - soft, r, d)
                        let reachable = 1 - resistance * (1 - paper.height(x: px, y: py))
                        let lift = amount * coverage * reachable
                        let index = row + px
                        if lift > buffer[index] { buffer[index] = lift }
                    }
                }
            }
        }
        return area
    }
}

extension GraphiteMath {
    /// Rubbing with an eraser lifts that fraction of the graphite.
    @inline(__always)
    static func erase(base: Float, lift: Float) -> Float {
        base * (1 - lift)
    }
}
