import CoreGraphics
import Foundation

/// One shape cut through a template, in millimetres about the template's centre.
struct TemplateCut: Sendable {
    /// The cut's rim, closed.
    var outline: [CGPoint]
    var center: CGPoint
    /// Its marked size, printed beside it.
    var label: String
    /// Half its width and height, for placing the label and the axis marks.
    var halfSize: CGSize
    /// Whether short marks on its axes help line it up with centre lines.
    var axisMarks: Bool
    /// Where its size is printed, if not just above it.
    var labelAt: CGPoint? = nil
}

/// The shape templates (형판) other than the circle template: thin tinted
/// sheets with shapes cut through them, each cut a little larger than its
/// marked size so a lead run round inside it draws that size.
enum ShapeTemplate {
    /// How a cut is drawn: its rim about its own centre, for a marked size.
    private struct Item {
        var size: Double
        var label: String
        var rim: (Double) -> [CGPoint]
        var halfSize: (Double) -> CGSize
        var axisMarks: Bool
    }

    static let marginMM = 7.0
    static let gapMM = 4.0
    /// Room above each cut for its size.
    static let labelMM = 4.0
    /// Each cut is this much larger all round than its marked size.
    static let leadAllowanceMM = 0.25

    /// Isometric ellipses: minor axis 0.577 of the major (a circle seen at 35°16′).
    static let isometricRatio = 1 / 3.0.squareRoot()

    static func name(_ kind: ToolKind) -> String {
        switch kind {
        case .ellipseTemplate: "타원"
        case .squareTemplate: "사각·삼각"
        case .hexTemplate: "육각·팔각"
        case .arcTemplate: "원주 1/4"
        default: "원"
        }
    }

    private static func rows(_ kind: ToolKind) -> [[Item]] {
        let a = leadAllowanceMM
        func ellipse(_ major: Double) -> Item {
            Item(size: major, label: "\(Int(major))", rim: { m in
                (0..<96).map { k in
                    let t = Double(k) / 96 * 2 * .pi
                    return CGPoint(x: cos(t) * (m / 2 + a), y: sin(t) * (m / 2 * isometricRatio + a))
                }
            }, halfSize: { m in CGSize(width: m / 2 + a, height: m / 2 * isometricRatio + a) }, axisMarks: true)
        }
        func polygon(_ size: Double, sides: Int, label: String, turned: Double, acrossFlats: Bool) -> Item {
            // `size` is the side for squares and triangles, the width across flats for the rest.
            let circumradius: Double
            if acrossFlats {
                circumradius = size / 2 / cos(.pi / Double(sides))
            } else {
                circumradius = size / (2 * sin(.pi / Double(sides)))
            }
            let r = circumradius + a / cos(.pi / Double(sides))
            let corners = (0..<sides).map { k -> CGPoint in
                let t = turned + Double(k) / Double(sides) * 2 * .pi
                return CGPoint(x: cos(t) * r, y: sin(t) * r)
            }
            let ys = corners.map(\.y), xs = corners.map(\.x)
            // Centre the shape on its own bounding box, so triangles sit level in their row.
            let dy = ((ys.max() ?? 0) + (ys.min() ?? 0)) / 2
            let centred = corners.map { CGPoint(x: $0.x, y: $0.y - dy) }
            let half = CGSize(width: ((xs.max() ?? 0) - (xs.min() ?? 0)) / 2, height: ((ys.max() ?? 0) - (ys.min() ?? 0)) / 2)
            return Item(size: size, label: label, rim: { _ in centred }, halfSize: { _ in half }, axisMarks: false)
        }
        switch kind {
        case .ellipseTemplate:
            return [[8, 10, 12, 14, 16, 18, 20].map(ellipse), [24, 28, 32, 36].map(ellipse)]
        case .squareTemplate:
            return [
                [4, 6, 8, 10, 12, 15, 18, 20].map { polygon($0, sides: 4, label: "\(Int($0))", turned: .pi / 4, acrossFlats: false) },
                [6, 8, 10, 14, 18, 22, 26].map { polygon($0, sides: 3, label: "\(Int($0))", turned: -.pi / 2, acrossFlats: false) },
            ]
        case .hexTemplate:
            return [
                [5, 7, 9, 11, 13, 16, 19, 22].map { polygon($0, sides: 6, label: "\(Int($0))", turned: 0, acrossFlats: true) },
                [8, 10, 13, 16, 20, 24].map { polygon($0, sides: 8, label: "\(Int($0))", turned: .pi / 8, acrossFlats: true) },
            ]
        default:
            return []
        }
    }

    /// The template's cuts and its overall size, laid out row by row.
    static let layouts: [ToolKind: (size: CGSize, cuts: [TemplateCut])] = {
        var out: [ToolKind: (size: CGSize, cuts: [TemplateCut])] = [:]
        for kind in [ToolKind.ellipseTemplate, .squareTemplate, .hexTemplate] {
            let rows = rows(kind)
            let rowWidths = rows.map { row in row.reduce(0) { $0 + 2 * Double($1.halfSize($1.size).width) } + gapMM * Double(row.count - 1) }
            let rowHeights = rows.map { row in row.map { 2 * Double($0.halfSize($0.size).height) }.max() ?? 0 }
            let width = (rowWidths.max() ?? 0) + 2 * marginMM
            let height = rowHeights.reduce(0) { $0 + $1 + labelMM } + gapMM * Double(rows.count - 1) + 2 * marginMM
            var cuts: [TemplateCut] = []
            var y = -height / 2 + marginMM
            for (row, items) in rows.enumerated() {
                y += labelMM
                let centreY = y + rowHeights[row] / 2
                var x = -rowWidths[row] / 2
                for item in items {
                    let half = item.halfSize(item.size)
                    let cx = x + Double(half.width)
                    let rim = item.rim(item.size).map { CGPoint(x: Double($0.x) + cx, y: Double($0.y) + centreY) }
                    cuts.append(TemplateCut(outline: rim, center: CGPoint(x: cx, y: centreY), label: item.label,
                                            halfSize: half, axisMarks: item.axisMarks))
                    x += 2 * Double(half.width) + gapMM
                }
                y += rowHeights[row] + gapMM
            }
            out[kind] = (CGSize(width: width, height: height), cuts)
        }
        out[.arcTemplate] = arcLayout()
        return out
    }()

    // MARK: Quarter-circle radius template (원주 형판)

    /// A square plate with quarter-circle slots round one corner, for arcs
    /// too big for a circle template. The pencil runs in a slot; its marked
    /// radius is the slot's middle.
    static let arcPlateMM = 250.0
    /// The slots' common centre, in from the plate's lower left corner.
    static let arcCentreInsetMM = 12.0
    static let arcRadiiMM: [Double] = [25, 40, 55, 70, 85, 100, 115, 130, 145, 160, 175, 190, 205, 220]
    static let arcSlotWidthMM = 2.5
    /// Each slot stops short of the plate's edges by this angle, so the plate holds together.
    static let arcEndDegrees = 3.0

    static var arcCentre: CGPoint {
        CGPoint(x: -arcPlateMM / 2 + arcCentreInsetMM, y: arcPlateMM / 2 - arcCentreInsetMM)
    }

    private static func arcLayout() -> (size: CGSize, cuts: [TemplateCut]) {
        let c = arcCentre, w = arcSlotWidthMM / 2
        // Up the left side (−90°, pointing up) round to the bottom (0°, pointing right).
        let from = (-90 + arcEndDegrees) * .pi / 180, to = -arcEndDegrees * .pi / 180
        func at(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: Double(c.x) + cos(a) * r, y: Double(c.y) + sin(a) * r) }
        let cuts = arcRadiiMM.map { r -> TemplateCut in
            let steps = max(Int((to - from) * r / 1.0), 24)
            var rim: [CGPoint] = (0...steps).map { at(r + w, from + (to - from) * Double($0) / Double(steps)) }
            // Round end at `to`, from the outer rim to the inner.
            rim += (1..<12).map { k in
                let end = at(r, to), a = to + Double(k) / 12 * .pi
                return CGPoint(x: Double(end.x) + cos(a) * w, y: Double(end.y) + sin(a) * w)
            }
            rim += (0...steps).map { at(r - w, to - (to - from) * Double($0) / Double(steps)) }
            rim += (1..<12).map { k in
                let end = at(r, from), a = from + .pi + Double(k) / 12 * .pi
                return CGPoint(x: Double(end.x) + cos(a) * w, y: Double(end.y) + sin(a) * w)
            }
            return TemplateCut(outline: rim, center: c, label: "R\(Int(r))", halfSize: CGSize(width: r + w, height: r + w),
                               axisMarks: false, labelAt: at(r + 6.5, -.pi / 4))
        }
        return (CGSize(width: arcPlateMM, height: arcPlateMM), cuts)
    }

    static func size(_ kind: ToolKind) -> CGSize { layouts[kind]?.size ?? .zero }
    static func cuts(_ kind: ToolKind) -> [TemplateCut] { layouts[kind]?.cuts ?? [] }
}
