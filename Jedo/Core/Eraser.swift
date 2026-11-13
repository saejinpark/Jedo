import CoreGraphics
import Foundation

/// How a rub of the eraser takes graphite off. A finger rubs with it; the
/// pencil keeps drawing. (Turning the pencil into the eraser was the other
/// draft compared on the iPad; rubbing with a finger was chosen.)
struct EraserDynamics: Sendable {
    let pixelsPerMillimeter: Double
    var kind: EraserKind = .rubber

    /// The worn corner of a drafting eraser (the rubber's width; kept for older callers).
    static let widthMM = EraserKind.rubber.widthMM
    static let valleyResistance = EraserKind.rubber.valleyResistance

    var radius: Double { kind.widthMM / 2 * pixelsPerMillimeter }
    var spacing: Double { max(radius * 0.2, 0.5) }

    func strength(for sample: StrokeSample) -> Double {
        min(kind.baseStrength + kind.pressureStrength * sample.pressure, kind.maxStrength)
    }
}

/// The erasers on a drafting desk. Each takes graphite off its own way, and
/// none is free: the rubber still needs going over, which is what makes a
/// line worth drawing carefully the first time.
enum EraserKind: CaseIterable, Hashable, Sendable {
    /// The plastic drafting eraser: lifts a share each pass, leaves a ghost in the grain.
    case rubber
    /// Kneaded rubber, dabbed and rolled: lightens a line evenly without taking it all.
    case kneaded
    /// The electric eraser: a small spinning strip that takes a line clean in a pass.
    case electric

    var name: String {
        switch self {
        case .rubber: "고무"
        case .kneaded: "떡"
        case .electric: "전동"
        }
    }

    /// How readily it takes ink, against graphite. India ink sits in the paper:
    /// rubber barely moves it; the electric eraser's abrasive strip grinds it off.
    var inkLift: Float {
        switch self {
        case .rubber: 0.04
        case .kneaded: 0
        case .electric: 0.55
        }
    }

    /// Width of the part that touches the paper.
    var widthMM: Double {
        switch self {
        case .rubber: 5
        case .kneaded: 9
        case .electric: 2.5
        }
    }

    /// Share of the graphite one light rub lifts, and how much more a firm one does.
    var baseStrength: Double {
        switch self {
        case .rubber: 0.25
        case .kneaded: 0.12
        case .electric: 0.97
        }
    }

    var pressureStrength: Double {
        switch self {
        case .rubber: 0.45
        case .kneaded: 0.16
        case .electric: 0
        }
    }

    /// The most one pass can lift.
    var maxStrength: Double {
        switch self {
        case .rubber: 0.95
        case .kneaded: 0.3
        case .electric: 0.97
        }
    }

    /// How much harder the graphite in the paper's valleys is to reach than on its peaks.
    var valleyResistance: Double {
        switch self {
        case .rubber: 0.3
        case .kneaded: 0.05
        case .electric: 0.02
        }
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
                      paper: PaperTexture, valleyResistance: Double = EraserKind.rubber.valleyResistance) -> PixelRect {
        guard center.x.isFinite, center.y.isFinite, radius > 0, strength > 0 else { return .empty }
        let area = bounds(center: center, radius: radius).intersection(raster.bounds)
        guard !area.isEmpty else { return .empty }

        let cx = Float(center.x), cy = Float(center.y)
        let r = Float(radius)
        let soft = max(r * 0.3, 1)
        let amount = Float(strength)
        let resistance = Float(valleyResistance)
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
