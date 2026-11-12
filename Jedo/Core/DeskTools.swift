import CoreGraphics
import Foundation

/// The rigid tools that can lie on the paper.
enum ToolKind: String, CaseIterable, Hashable, Sendable {
    case ruler
    /// 45° set square.
    case setSquare45
    /// 30°/60° set square.
    case setSquare60
    /// A plastic sheet of round holes.
    case circleTemplate
    /// A French curve: one acrylic outline of ever-changing curvature.
    case frenchCurve
    /// A long bamboo hip curve, gently bending, as used in pattern drafting.
    case hipCurve
}

/// A tool lying on the paper.
struct DeskTool: Equatable, Sendable {
    var kind: ToolKind
    var pose: ToolPose

    func shape(pixelsPerMillimeter ppmm: Double) -> ToolShape {
        switch kind {
        case .ruler:
            return Ruler(pose: pose, pixelsPerMillimeter: ppmm).shape
        case .setSquare45, .setSquare60:
            return ToolShape(pose: pose, outline: SetSquare.cornersMM(kind).map { $0.scaled(ppmm) })
        case .circleTemplate:
            let w = CircleTemplate.widthMM / 2 * ppmm, h = CircleTemplate.heightMM / 2 * ppmm
            return ToolShape(
                pose: pose,
                outline: [CGPoint(x: -w, y: -h), CGPoint(x: w, y: -h), CGPoint(x: w, y: h), CGPoint(x: -w, y: h)],
                holes: CircleTemplate.holes.map {
                    ToolShape.Hole(center: $0.center.scaled(ppmm), radius: CircleTemplate.holeRadiusMM($0.diameter) * ppmm)
                }
            )
        case .frenchCurve:
            return ToolShape(pose: pose, outline: CurveTools.frenchCurveMM.map { $0.scaled(ppmm) }, smooth: true)
        case .hipCurve:
            return ToolShape(pose: pose, outline: CurveTools.hipCurveMM.map { $0.scaled(ppmm) }, smooth: true)
        }
    }
}

/// Drafting set squares: solid right triangles whose three sides all guide the pencil.
enum SetSquare {
    /// Both legs of the 45° square.
    static let legMM45 = 100.0
    /// The short leg of the 30°/60° square; the long leg is √3 times it.
    static let shortLegMM60 = 65.0

    /// Corners in millimetres, right angle first, about the triangle's centroid.
    /// The right angle sits bottom left, legs running right and up.
    static func cornersMM(_ kind: ToolKind) -> [CGPoint] {
        let (along, up): (Double, Double) = switch kind {
        case .setSquare60: (shortLegMM60 * 3.0.squareRoot(), shortLegMM60)
        default: (legMM45, legMM45)
        }
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: along, y: 0), CGPoint(x: 0, y: -up)]
        let cx = along / 3, cy = -up / 3
        return corners.map { CGPoint(x: Double($0.x) - cx, y: Double($0.y) - cy) }
    }
}

/// A circle template: a row of small holes over a row of larger ones.
enum CircleTemplate {
    static let widthMM = 140.0
    static let heightMM = 66.0
    /// Nominal diameters, by row.
    static let rowsMM: [[Double]] = [[3, 4, 5, 6, 8, 10, 12, 14, 16], [18, 20, 22, 25, 28]]
    /// Row centres, from the template's centre.
    static let rowCentersMM: [Double] = [-18, 12]
    static let gapMM = 3.0
    /// Holes are cut this much wider than their size, so a lead running
    /// round the inside draws a circle of the marked size.
    static let leadAllowanceMM = 0.25

    static func holeRadiusMM(_ diameter: Double) -> Double { diameter / 2 + leadAllowanceMM }

    /// Every hole's centre (mm, from the template's centre) and marked diameter.
    static let holes: [(center: CGPoint, diameter: Double)] = {
        var out: [(CGPoint, Double)] = []
        for (row, diameters) in rowsMM.enumerated() {
            let total = diameters.reduce(0, +) + gapMM * Double(diameters.count - 1)
            var x = -total / 2
            for d in diameters {
                out.append((CGPoint(x: x + d / 2, y: rowCentersMM[row]), d))
                x += d + gapMM
            }
        }
        return out
    }()
}

extension CGPoint {
    func scaled(_ factor: Double) -> CGPoint { CGPoint(x: Double(x) * factor, y: Double(y) * factor) }
}
