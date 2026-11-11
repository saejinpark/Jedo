import CoreGraphics
import Foundation

/// Lays one dab of graphite into a stroke buffer.
///
/// Within a stroke the buffer keeps the strongest deposit at each pixel
/// (it does not add), so a line is even however densely the dabs overlap.
/// Darkening from going over a line again happens later, when strokes are
/// composited onto the sheet.
enum DabRasterizer {
    /// How strongly the lead itself is grainy, on top of the paper's tooth.
    static let leadNoise: Float = 0.12
    /// Width of the grain threshold's soft step, in paper-height units.
    static let grainSoftness: Float = 0.24

    /// Pixels a dab can touch.
    static func bounds(center: CGPoint, shape: DabShape) -> PixelRect {
        let reach = 1 + shape.edgeSoftness / 2
        let a = shape.radiusAlong * reach + 1
        let b = shape.radiusAcross * reach + 1
        let c = cos(shape.angle), s = sin(shape.angle)
        let ex = (a * a * c * c + b * b * s * s).squareRoot()
        let ey = (a * a * s * s + b * b * c * c).squareRoot()
        guard ex.isFinite, ey.isFinite, center.x.isFinite, center.y.isFinite else { return .empty }
        return PixelRect(minX: Int((center.x - ex).rounded(.down)), minY: Int((center.y - ey).rounded(.down)),
                         maxX: Int((center.x + ex).rounded(.up)) + 1, maxY: Int((center.y + ey).rounded(.up)) + 1)
    }

    /// Returns the pixels it may have changed.
    @discardableResult
    static func stamp(center: CGPoint, shape: DabShape, into raster: inout GraphiteRaster,
                      paper: PaperTexture, seed: UInt32) -> PixelRect {
        let area = bounds(center: center, shape: shape).intersection(raster.bounds)
        guard !area.isEmpty, shape.opacity > 0 else { return .empty }

        let cx = Float(center.x), cy = Float(center.y)
        let cosA = Float(cos(shape.angle)), sinA = Float(sin(shape.angle))
        let invA = 1 / Float(max(shape.radiusAlong, 0.01))
        let invB = 1 / Float(max(shape.radiusAcross, 0.01))
        // At least one pixel of antialiasing, however small the dab.
        let edge = min(max(Float(shape.edgeSoftness), 1 / Float(max(shape.minRadius, 0.01))), 1.5)
        let inner = max(1 - edge / 2, 0)
        let outer = 1 + edge / 2
        let outerSquared = outer * outer
        let opacity = Float(shape.opacity)
        let threshold = Float(shape.grainThreshold)
        let grainLow = threshold - grainSoftness
        let grainHigh = threshold + grainSoftness
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
                        let u = (dx * cosA + dy * sinA) * invA
                        let v = (dy * cosA - dx * sinA) * invB
                        let q = u * u + v * v
                        if q >= outerSquared { continue }
                        let coverage = 1 - smoothstepF(inner, outer, q.squareRoot())
                        let grain = smoothstepF(grainLow, grainHigh, paper.height(x: px, y: py))
                        let lead = 1 - leadNoise * pixelHash(px, py, seed)
                        let deposit = opacity * coverage * grain * lead
                        let index = row + px
                        if deposit > buffer[index] { buffer[index] = deposit }
                    }
                }
            }
        }
        return area
    }
}

/// How strokes build up on the sheet.
enum GraphiteMath {
    /// Laying a stroke of strength `stroke` over existing density `base` closes
    /// that fraction of the gap to the lead's darkest. Going over a line again
    /// darkens it, ever more slowly, and a hard lead cannot lighten or exceed
    /// what a soft one already laid.
    @inline(__always)
    static func composite(base: Float, stroke: Float, maxDensity: Float) -> Float {
        base + max(maxDensity - base, 0) * stroke
    }
}

@inline(__always)
func smoothstepF(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    guard edge0 != edge1 else { return x < edge0 ? 0 : 1 }
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
