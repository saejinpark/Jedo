import UIKit

/// The face of a triangular scale that lies up: pale grey plastic with a
/// reduction scale along each edge. Every millimetre is a tick; the numbers
/// read in metres at the scale of that edge.
final class ScaleRuleView: UIView, ToolDisplay {
    private var pointsPerMM: CGFloat = 5
    private var face = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isHidden = true
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1.5)
        accessibilityLabel = tr("삼각 스케일")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ tool: DeskTool, scale: CGFloat, pixelsPerMillimeter: Double) {
        let ptPerMM = CGFloat(pixelsPerMillimeter) / scale
        let size = CGSize(width: CGFloat(ScaleRule.lengthMM) * ptPerMM, height: CGFloat(ScaleRule.widthMM) * ptPerMM)
        if bounds.size != size || ptPerMM != pointsPerMM || face != tool.face {
            pointsPerMM = ptPerMM
            face = tool.face
            bounds = CGRect(origin: .zero, size: size)
            layer.shadowPath = UIBezierPath(rect: bounds).cgPath
            setNeedsDisplay()
        }
        center = CGPoint(x: tool.pose.center.x / scale, y: tool.pose.center.y / scale)
        transform = CGAffineTransform(rotationAngle: tool.pose.angle)
        isHidden = false
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let mm = pointsPerMM
        // Two faces of the prism meet along the middle: a ridge.
        UIColor(red: 0.93, green: 0.93, blue: 0.91, alpha: 0.92).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height / 2))
        UIColor(red: 0.86, green: 0.86, blue: 0.84, alpha: 0.92).setFill()
        UIRectFill(CGRect(x: 0, y: bounds.height / 2, width: bounds.width, height: bounds.height / 2))
        let ink = UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.9)
        UIColor(white: 0.45, alpha: 0.6).setStroke()
        ctx.setLineWidth(0.6)
        ctx.stroke(bounds.insetBy(dx: 0.3, dy: 0.3))
        ctx.move(to: CGPoint(x: 0, y: bounds.height / 2))
        ctx.addLine(to: CGPoint(x: bounds.width, y: bounds.height / 2))
        ctx.strokePath()

        let pair = ScaleRule.faces[min(max(face, 0), ScaleRule.faces.count - 1)]
        let start = CGFloat(ScaleRule.lengthMM - 300) / 2 * mm
        let font = UIFont.monospacedDigitSystemFont(ofSize: 2.4 * mm, weight: .medium)
        let tag = UIFont.systemFont(ofSize: 2.3 * mm, weight: .semibold)
        for (edge, ratio) in [(0, pair.upper), (1, pair.lower)] {
            let y0: CGFloat = edge == 0 ? 0 : bounds.height
            let dir: CGFloat = edge == 0 ? 1 : -1
            ink.setStroke()
            ctx.setLineWidth(0.45)
            for tick in 0...300 {
                let x = start + CGFloat(tick) * mm
                let length: CGFloat = tick % 10 == 0 ? 4 : tick % 5 == 0 ? 2.8 : 1.6
                ctx.move(to: CGPoint(x: x, y: y0))
                ctx.addLine(to: CGPoint(x: x, y: y0 + dir * length * mm))
            }
            ctx.strokePath()
            // Every centimetre of paper is ratio/100 metres.
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            for cm in stride(from: 0, through: 30, by: 1) {
                let metres = cm * ratio / 100
                let label = "\(metres)" as NSString
                let size = label.size(withAttributes: attributes)
                let x = start + CGFloat(cm * 10) * mm
                let y = edge == 0 ? 4.4 * mm : bounds.height - 4.4 * mm - size.height
                label.draw(at: CGPoint(x: x - size.width / 2, y: y), withAttributes: attributes)
            }
            let name = "1:\(ratio)" as NSString
            let nameAttributes: [NSAttributedString.Key: Any] = [.font: tag, .foregroundColor: UIColor(red: 0.62, green: 0.13, blue: 0.12, alpha: 0.9)]
            let nameSize = name.size(withAttributes: nameAttributes)
            name.draw(at: CGPoint(x: 1 * mm, y: edge == 0 ? 6 * mm : bounds.height - 6 * mm - nameSize.height), withAttributes: nameAttributes)
        }
    }
}
