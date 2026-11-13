import UIKit

/// A view showing one tool over the paper, in the paper's coordinates.
@MainActor
protocol ToolDisplay: UIView {
    func show(_ tool: DeskTool, scale: CGFloat, pixelsPerMillimeter: Double)
}

extension RulerView: ToolDisplay {
    func show(_ tool: DeskTool, scale: CGFloat, pixelsPerMillimeter: Double) {
        show(Ruler(pose: tool.pose, pixelsPerMillimeter: pixelsPerMillimeter), scale: scale, pixelsPerMillimeter: pixelsPerMillimeter)
    }
}

/// A tool drawn from its outline in its own frame, in millimetres. The view
/// turns about the tool's own origin, so its pose maps straight onto it.
class OutlineToolView: UIView, ToolDisplay {
    let kind: ToolKind
    private(set) var pointsPerMM: CGFloat = 5
    /// The outline's top-left corner, in the tool's millimetres.
    private(set) var cornerMM = CGPoint.zero

    init(kind: ToolKind) {
        self.kind = kind
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isHidden = true
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1.5)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The outline, in the tool's millimetres.
    var outlineMM: [CGPoint] { [] }

    func show(_ tool: DeskTool, scale: CGFloat, pixelsPerMillimeter: Double) {
        let ptPerMM = CGFloat(pixelsPerMillimeter) / scale
        let xs = outlineMM.map(\.x), ys = outlineMM.map(\.y)
        let corner = CGPoint(x: xs.min() ?? 0, y: ys.min() ?? 0)
        let sizeMM = CGSize(width: (xs.max() ?? 0) - corner.x, height: (ys.max() ?? 0) - corner.y)
        let size = CGSize(width: sizeMM.width * ptPerMM, height: sizeMM.height * ptPerMM)
        if bounds.size != size || ptPerMM != pointsPerMM {
            pointsPerMM = ptPerMM
            cornerMM = corner
            bounds = CGRect(origin: .zero, size: size)
            layer.anchorPoint = CGPoint(x: -corner.x / sizeMM.width, y: -corner.y / sizeMM.height)
            layer.shadowPath = bodyPath().cgPath
            setNeedsDisplay()
        }
        center = CGPoint(x: tool.pose.center.x / scale, y: tool.pose.center.y / scale)
        transform = CGAffineTransform(rotationAngle: tool.pose.angle)
        isHidden = false
    }

    /// A point given in the tool's millimetres, in this view's points.
    func pt(_ mm: CGPoint) -> CGPoint {
        CGPoint(x: (mm.x - cornerMM.x) * pointsPerMM, y: (mm.y - cornerMM.y) * pointsPerMM)
    }

    /// The tool's body, holes cut out.
    func bodyPath() -> UIBezierPath {
        let path = UIBezierPath()
        for (i, p) in outlineMM.enumerated() {
            i == 0 ? path.move(to: pt(p)) : path.addLine(to: pt(p))
        }
        path.close()
        return path
    }

    static let ink = UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.85)
    static let rim = UIColor(red: 0.36, green: 0.36, blue: 0.36, alpha: 0.55)
}

/// A smoky-grey acrylic set square: graduations along its bottom leg, its angles marked.
final class SetSquareView: OutlineToolView {
    override var outlineMM: [CGPoint] { SetSquare.cornersMM(kind) }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let body = bodyPath()
        UIColor(red: 0.80, green: 0.80, blue: 0.79, alpha: 0.32).setFill()
        body.fill()
        Self.rim.setStroke()
        body.lineWidth = 0.6
        body.stroke()

        let c = outlineMM
        // A bevel line just inside every edge.
        let inset = 2.0, centre = CGPoint(x: (c[0].x + c[1].x + c[2].x) / 3, y: (c[0].y + c[1].y + c[2].y) / 3)
        let bevel = UIBezierPath()
        for (i, p) in c.enumerated() {
            let toward = CGPoint(x: centre.x - p.x, y: centre.y - p.y)
            let len = hypot(toward.x, toward.y)
            let q = CGPoint(x: p.x + toward.x / len * inset * 2.2, y: p.y + toward.y / len * inset * 2.2)
            i == 0 ? bevel.move(to: pt(q)) : bevel.addLine(to: pt(q))
        }
        bevel.close()
        UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 0.30).setStroke()
        bevel.lineWidth = 0.5
        bevel.stroke()

        // Millimetres along the bottom leg, from the right angle.
        Self.ink.setStroke()
        ctx.setLineWidth(0.5)
        let font = UIFont.monospacedDigitSystemFont(ofSize: 2.4 * pointsPerMM, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Self.ink]
        let legMM = Int(c[1].x - c[0].x) - 25
        for mm in 0...max(legMM, 0) {
            let x = c[0].x + 8 + CGFloat(mm)
            let length: CGFloat = mm % 10 == 0 ? 4 : mm % 5 == 0 ? 2.8 : 1.6
            ctx.move(to: pt(CGPoint(x: x, y: c[0].y)))
            ctx.addLine(to: pt(CGPoint(x: x, y: c[0].y - length)))
            if mm % 10 == 0 {
                let label = "\(mm / 10)" as NSString
                let size = label.size(withAttributes: attributes)
                let at = pt(CGPoint(x: x, y: c[0].y - 4.6))
                label.draw(at: CGPoint(x: at.x - size.width / 2, y: at.y - size.height), withAttributes: attributes)
            }
        }
        ctx.strokePath()

        let name = (kind == .setSquare45 ? "45°" : "30°  60°") as NSString
        let nameFont = UIFont.systemFont(ofSize: 3.4 * pointsPerMM, weight: .semibold)
        let nameAttributes: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: Self.ink.withAlphaComponent(0.55)]
        let at = pt(CGPoint(x: c[0].x + 12, y: c[0].y - 16))
        name.draw(at: at, withAttributes: nameAttributes)
    }
}

/// A tinted plastic circle template: holes with their sizes and quarter marks.
final class CircleTemplateView: OutlineToolView {
    init() { super.init(kind: .circleTemplate) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var outlineMM: [CGPoint] {
        let w = CircleTemplate.widthMM / 2, h = CircleTemplate.heightMM / 2
        return [CGPoint(x: -w, y: -h), CGPoint(x: w, y: -h), CGPoint(x: w, y: h), CGPoint(x: -w, y: h)]
    }

    private func holePath(_ hole: (center: CGPoint, diameter: Double)) -> UIBezierPath {
        let r = CircleTemplate.holeRadiusMM(hole.diameter) * pointsPerMM
        let c = pt(hole.center)
        return UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    override func bodyPath() -> UIBezierPath {
        let path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), cornerRadius: 3 * pointsPerMM)
        for hole in CircleTemplate.holes { path.append(holePath(hole).reversing()) }
        return path
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let body = bodyPath()
        body.usesEvenOddFillRule = true
        UIColor(red: 0.97, green: 0.88, blue: 0.62, alpha: 0.34).setFill()
        body.fill()
        Self.rim.setStroke()
        body.lineWidth = 0.6
        body.stroke()

        let font = UIFont.monospacedDigitSystemFont(ofSize: 2.4 * pointsPerMM, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Self.ink]
        Self.ink.setStroke()
        ctx.setLineWidth(0.5)
        for hole in CircleTemplate.holes {
            let r = CircleTemplate.holeRadiusMM(hole.diameter)
            // Quarter marks, to line a hole up with crossed centre lines.
            for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                ctx.move(to: pt(CGPoint(x: hole.center.x + dx * (r + 0.4), y: hole.center.y + dy * (r + 0.4))))
                ctx.addLine(to: pt(CGPoint(x: hole.center.x + dx * (r + 1.8), y: hole.center.y + dy * (r + 1.8))))
            }
            let label = (hole.diameter == hole.diameter.rounded() ? "\(Int(hole.diameter))" : "\(hole.diameter)") as NSString
            let size = label.size(withAttributes: attributes)
            let top = pt(CGPoint(x: hole.center.x, y: hole.center.y - r - 2.2))
            label.draw(at: CGPoint(x: top.x - size.width / 2, y: top.y - size.height), withAttributes: attributes)
        }
        ctx.strokePath()
    }
}

/// A smoky orange acrylic French curve (운형자) with its slot.
final class FrenchCurveView: OutlineToolView {
    override var outlineMM: [CGPoint] { FrenchCurve.outline(kind) }

    override func bodyPath() -> UIBezierPath {
        let path = super.bodyPath()
        let outward = Self.signedArea(outlineMM) > 0
        for outline in FrenchCurve.slots(kind) {
            // A hole must wind the other way, or the shadow fills it.
            let ordered = (Self.signedArea(outline) > 0) == outward ? outline.reversed() : outline
            let slot = UIBezierPath()
            for (i, p) in ordered.enumerated() {
                i == 0 ? slot.move(to: pt(p)) : slot.addLine(to: pt(p))
            }
            slot.close()
            path.append(slot)
        }
        return path
    }

    static func signedArea(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst() + points.prefix(1)).reduce(0) { $0 + Double($1.0.x * $1.1.y - $1.1.x * $1.0.y) } / 2
    }

    override func draw(_ rect: CGRect) {
        let body = bodyPath()
        body.usesEvenOddFillRule = true
        UIColor(red: 0.98, green: 0.72, blue: 0.42, alpha: 0.30).setFill()
        body.fill()
        UIColor(red: 0.62, green: 0.40, blue: 0.20, alpha: 0.55).setStroke()
        body.lineWidth = 0.6
        body.stroke()

        // The set number, as cut into the plastic.
        if let index = ToolKind.frenchCurves.firstIndex(of: kind) {
            let label = "\(index + 1)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 3.4 * pointsPerMM, weight: .semibold),
                .foregroundColor: UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 0.55),
            ]
            let size = label.size(withAttributes: attributes)
            let at = labelSpot()
            label.draw(at: CGPoint(x: at.x - size.width / 2, y: at.y - size.height / 2), withAttributes: attributes)
        }
    }

    /// The widest part of the plastic.
    private func labelSpot() -> CGPoint { pt(FrenchCurve.labelSpot(kind)) }
}

/// A long bamboo hip curve: opaque, with its grain and a centimetre scale
/// along the convex edge.
final class HipCurveView: OutlineToolView {
    init() { super.init(kind: .hipCurve) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var outlineMM: [CGPoint] { CurveTools.hipCurveMM }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let body = bodyPath()
        UIColor(red: 0.86, green: 0.72, blue: 0.49, alpha: 0.95).setFill()
        body.fill()

        // Grain: a few fibres running the length.
        let edges = CurveTools.hipCurveEdgesMM
        ctx.saveGState()
        body.addClip()
        for (k, fraction) in [0.18, 0.33, 0.52, 0.71, 0.86].enumerated() {
            let fibre = UIBezierPath()
            for (i, (a, b)) in zip(edges.scale, edges.inner).enumerated() {
                let p = pt(CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction))
                i == 0 ? fibre.move(to: p) : fibre.addLine(to: p)
            }
            UIColor(red: 0.62, green: 0.47, blue: 0.27, alpha: k % 2 == 0 ? 0.28 : 0.16).setStroke()
            fibre.lineWidth = k % 2 == 0 ? 0.8 : 0.5
            fibre.stroke()
        }
        ctx.restoreGState()

        UIColor(red: 0.48, green: 0.34, blue: 0.17, alpha: 0.75).setStroke()
        body.lineWidth = 0.7
        body.stroke()

        // Millimetres along the convex edge, measured along the curve.
        let scale = edges.scale, inner = edges.inner
        let ink = UIColor(red: 0.22, green: 0.15, blue: 0.08, alpha: 0.85)
        ink.setStroke()
        ctx.setLineWidth(0.5)
        let font = UIFont.monospacedDigitSystemFont(ofSize: 2.4 * pointsPerMM, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        var travelled = 0.0, nextMark = 5.0, mark = 5
        for i in 1..<scale.count {
            let a = scale[i - 1], b = scale[i]
            let step = hypot(Double(b.x - a.x), Double(b.y - a.y))
            while travelled + step >= nextMark {
                let t = (nextMark - travelled) / step
                let at = CGPoint(x: Double(a.x) + Double(b.x - a.x) * t, y: Double(a.y) + Double(b.y - a.y) * t)
                let into = CGPoint(x: inner[i].x - scale[i].x, y: inner[i].y - scale[i].y)
                let width = hypot(Double(into.x), Double(into.y))
                let length: Double = mark % 10 == 0 ? 4 : mark % 5 == 0 ? 2.8 : 1.6
                let end = CGPoint(x: Double(at.x) + Double(into.x) / width * length, y: Double(at.y) + Double(into.y) / width * length)
                ctx.move(to: pt(at))
                ctx.addLine(to: pt(end))
                if mark % 10 == 0 {
                    let label = "\(mark / 10)" as NSString
                    let size = label.size(withAttributes: attributes)
                    let spot = pt(CGPoint(x: Double(at.x) + Double(into.x) / width * 6.5, y: Double(at.y) + Double(into.y) / width * 6.5))
                    label.draw(at: CGPoint(x: spot.x - size.width / 2, y: spot.y - size.height / 2), withAttributes: attributes)
                }
                nextMark += 1
                mark += 1
            }
            travelled += step
        }
        ctx.strokePath()
    }
}

/// A smoky-grey acrylic protractor: degrees round the arc both ways, a base line
/// with its centre marked.
final class ProtractorView: OutlineToolView {
    init() { super.init(kind: .protractor) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var outlineMM: [CGPoint] { Protractor.outlineMM }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let body = bodyPath()
        UIColor(red: 0.80, green: 0.80, blue: 0.79, alpha: 0.32).setFill()
        body.fill()
        Self.rim.setStroke()
        body.lineWidth = 0.6
        body.stroke()

        let ink = Self.ink
        ink.setStroke()
        ctx.setLineWidth(0.45)
        // The base line and the centre mark.
        ctx.move(to: pt(CGPoint(x: -Protractor.radiusMM + 2, y: 0)))
        ctx.addLine(to: pt(CGPoint(x: Protractor.radiusMM - 2, y: 0)))
        ctx.move(to: pt(CGPoint(x: 0, y: -3)))
        ctx.addLine(to: pt(CGPoint(x: 0, y: 3)))
        // Degrees.
        for d in 0...180 {
            let length: Double = d % 10 == 0 ? 5 : d % 5 == 0 ? 3.2 : 1.8
            ctx.move(to: pt(Protractor.onArc(degree: Double(d))))
            ctx.addLine(to: pt(Protractor.onArc(degree: Double(d), inset: length)))
        }
        ctx.strokePath()
        // An inner arc the numbers sit against.
        let inner = UIBezierPath(arcCenter: pt(.zero), radius: (Protractor.radiusMM - 16) * pointsPerMM,
                                 startAngle: .pi, endAngle: 0, clockwise: true)
        UIColor(red: 0.36, green: 0.36, blue: 0.36, alpha: 0.35).setStroke()
        inner.lineWidth = 0.5
        inner.stroke()

        let outerFont = UIFont.monospacedDigitSystemFont(ofSize: 2.3 * pointsPerMM, weight: .medium)
        let innerFont = UIFont.monospacedDigitSystemFont(ofSize: 1.9 * pointsPerMM, weight: .regular)
        for d in stride(from: 0, through: 180, by: 10) {
            for (value, inset, font, alpha) in [(d, 8.0, outerFont, 0.9), (180 - d, 12.5, innerFont, 0.6)] {
                let label = "\(value)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink.withAlphaComponent(alpha)]
                let size = label.size(withAttributes: attributes)
                let at = pt(Protractor.onArc(degree: Double(d), inset: inset))
                label.draw(at: CGPoint(x: at.x - size.width / 2, y: at.y - size.height / 2), withAttributes: attributes)
            }
        }
    }
}

/// A tinted template sheet with shapes cut through it, each marked with its size.
final class ShapeTemplateView: OutlineToolView {
    override var outlineMM: [CGPoint] {
        let size = ShapeTemplate.size(kind)
        let w = size.width / 2, h = size.height / 2
        return [CGPoint(x: -w, y: -h), CGPoint(x: w, y: -h), CGPoint(x: w, y: h), CGPoint(x: -w, y: h)]
    }

    private var tint: UIColor {
        switch kind {
        case .ellipseTemplate: UIColor(red: 0.70, green: 0.88, blue: 0.70, alpha: 0.34)
        case .squareTemplate: UIColor(red: 0.66, green: 0.80, blue: 0.95, alpha: 0.34)
        case .arcTemplate: UIColor(red: 0.98, green: 0.76, blue: 0.22, alpha: 0.42)
        // Clear acrylic, like the rulers.
        case .letteringGuide: UIColor(red: 0.80, green: 0.80, blue: 0.79, alpha: 0.32)
        // Brushed steel: what lies under it shows only through the openings.
        case .erasingShield: UIColor(red: 0.74, green: 0.75, blue: 0.77, alpha: 0.9)
        default: UIColor(red: 0.95, green: 0.72, blue: 0.80, alpha: 0.34)
        }
    }

    override func bodyPath() -> UIBezierPath {
        let path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), cornerRadius: 3 * pointsPerMM)
        for cut in ShapeTemplate.cuts(kind) {
            let rim = UIBezierPath()
            for (i, p) in cut.outline.enumerated() {
                i == 0 ? rim.move(to: pt(p)) : rim.addLine(to: pt(p))
            }
            rim.close()
            path.append(rim.reversing())
        }
        return path
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let body = bodyPath()
        body.usesEvenOddFillRule = true
        tint.setFill()
        body.fill()
        Self.rim.setStroke()
        body.lineWidth = 0.6
        body.stroke()

        let font = UIFont.monospacedDigitSystemFont(ofSize: 2.3 * pointsPerMM, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Self.ink]
        Self.ink.setStroke()
        ctx.setLineWidth(0.5)
        for cut in ShapeTemplate.cuts(kind) {
            let half = cut.halfSize
            if cut.axisMarks {
                for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                    let reach = CGPoint(x: Double(half.width) * dx, y: Double(half.height) * dy)
                    ctx.move(to: pt(CGPoint(x: Double(cut.center.x + reach.x) + dx * 0.4, y: Double(cut.center.y + reach.y) + dy * 0.4)))
                    ctx.addLine(to: pt(CGPoint(x: Double(cut.center.x + reach.x) + dx * 1.8, y: Double(cut.center.y + reach.y) + dy * 1.8)))
                }
            }
            let label = cut.label as NSString
            let size = label.size(withAttributes: attributes)
            if let spot = cut.labelAt {
                let at = pt(spot)
                label.draw(at: CGPoint(x: at.x - size.width / 2, y: at.y - size.height / 2), withAttributes: attributes)
            } else {
                let top = pt(CGPoint(x: cut.center.x, y: cut.center.y - half.height - 1.2))
                label.draw(at: CGPoint(x: top.x - size.width / 2, y: top.y - size.height), withAttributes: attributes)
            }
        }
        ctx.strokePath()

        if kind == .arcTemplate {
            let c = ShapeTemplate.arcCentre
            Self.ink.setStroke()
            ctx.setLineWidth(0.6)
            ctx.move(to: pt(CGPoint(x: c.x - 4, y: c.y)))
            ctx.addLine(to: pt(CGPoint(x: c.x + 4, y: c.y)))
            ctx.move(to: pt(CGPoint(x: c.x, y: c.y - 4)))
            ctx.addLine(to: pt(CGPoint(x: c.x, y: c.y + 4)))
            ctx.strokePath()
        }

        let title = ShapeTemplate.name(kind) as NSString
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 2.6 * pointsPerMM, weight: .semibold),
            .foregroundColor: Self.ink.withAlphaComponent(0.5),
        ]
        title.draw(at: pt(CGPoint(x: -ShapeTemplate.size(kind).width / 2 + 2.5, y: -ShapeTemplate.size(kind).height / 2 + 1.5)),
                   withAttributes: titleAttributes)
    }
}

/// The parallel rule: a pale body on cables, its drawing edge a clear strip
/// along the top, a pulley housing at each end.
final class ParallelRuleView: OutlineToolView {
    override var outlineMM: [CGPoint] {
        let l = ParallelRule.lengthMM / 2, w = ParallelRule.widthMM / 2
        return [CGPoint(x: -l, y: -w), CGPoint(x: l, y: -w), CGPoint(x: l, y: w), CGPoint(x: -l, y: w)]
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let l = ParallelRule.lengthMM / 2, w = ParallelRule.widthMM / 2
        let body = bodyPath()
        UIColor(red: 0.86, green: 0.86, blue: 0.84, alpha: 0.62).setFill()
        body.fill()
        // The clear drawing edges, top and bottom.
        for (top, bottom) in [(-w, -w + 9), (w - 6, w)] {
            let strip = UIBezierPath(rect: CGRect(origin: pt(CGPoint(x: -l, y: top)),
                                                  size: CGSize(width: 2 * l * pointsPerMM, height: (bottom - top) * pointsPerMM)))
            UIColor(red: 0.80, green: 0.80, blue: 0.79, alpha: 0.22).setFill()
            ctx.setBlendMode(.copy)
            strip.fill()
            ctx.setBlendMode(.normal)
        }
        // Pulley housings.
        for x in [-l, l - 28] {
            let cap = UIBezierPath(roundedRect: CGRect(origin: pt(CGPoint(x: x, y: -w + 9)),
                                                       size: CGSize(width: 28 * pointsPerMM, height: (2 * w - 15) * pointsPerMM)),
                                   cornerRadius: 2 * pointsPerMM)
            UIColor(white: 0.42, alpha: 0.55).setFill()
            cap.fill()
        }
        // The cable, along the body.
        ctx.setStrokeColor(UIColor(white: 0.30, alpha: 0.35).cgColor)
        ctx.setLineWidth(0.6)
        ctx.move(to: pt(CGPoint(x: -l + 28, y: 2)))
        ctx.addLine(to: pt(CGPoint(x: l - 28, y: 2)))
        ctx.strokePath()
        Self.rim.setStroke()
        body.lineWidth = 0.6
        body.stroke()
        // The edges you draw along, a touch darker.
        ctx.setStrokeColor(Self.ink.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(0.8)
        ctx.move(to: pt(CGPoint(x: -l, y: -w))); ctx.addLine(to: pt(CGPoint(x: l, y: -w)))
        ctx.strokePath()
    }
}
