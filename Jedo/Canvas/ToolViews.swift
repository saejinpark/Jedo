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
    static let rim = UIColor(red: 0.35, green: 0.45, blue: 0.50, alpha: 0.55)
}

/// A clear acrylic set square: graduations along its bottom leg, its angles marked.
final class SetSquareView: OutlineToolView {
    override var outlineMM: [CGPoint] { SetSquare.cornersMM(kind) }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let body = bodyPath()
        UIColor(red: 0.88, green: 0.95, blue: 0.93, alpha: 0.32).setFill()
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
        UIColor(red: 0.55, green: 0.65, blue: 0.70, alpha: 0.30).setStroke()
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
