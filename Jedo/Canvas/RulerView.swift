import UIKit

/// A clear acrylic drafting ruler: graduations along the upper edge, a
/// bevelled lower edge. It only shows the ruler; the canvas handles touches.
final class RulerView: UIView {
    private var pointsPerMM: CGFloat = 5

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isHidden = true
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1.5)
        accessibilityLabel = "자"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Places the view over the ruler. Canvas pixels in, points out.
    func show(_ ruler: Ruler, scale: CGFloat, pixelsPerMillimeter: Double) {
        let ptPerMM = CGFloat(pixelsPerMillimeter) / scale
        let size = CGSize(width: CGFloat(ruler.length) / scale, height: CGFloat(ruler.width) / scale)
        if bounds.size != size || ptPerMM != pointsPerMM {
            pointsPerMM = ptPerMM
            bounds = CGRect(origin: .zero, size: size)
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 3).cgPath
            setNeedsDisplay()
        }
        center = CGPoint(x: ruler.pose.center.x / scale, y: ruler.pose.center.y / scale)
        transform = CGAffineTransform(rotationAngle: ruler.pose.angle)
        isHidden = false
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let body = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), cornerRadius: 3)

        // Clear plastic with a faint cool tint.
        UIColor(red: 0.90, green: 0.95, blue: 0.97, alpha: 0.30).setFill()
        body.fill()

        // Bevel along the lower edge.
        let bevel = bounds.height - 2.2 * pointsPerMM
        UIColor(red: 0.70, green: 0.80, blue: 0.85, alpha: 0.20).setFill()
        UIRectFillUsingBlendMode(CGRect(x: 0, y: bevel, width: bounds.width, height: bounds.height - bevel), .normal)

        UIColor(red: 0.35, green: 0.45, blue: 0.50, alpha: 0.55).setStroke()
        body.lineWidth = 0.6
        body.stroke()
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: 0, y: bevel))
        ctx.addLine(to: CGPoint(x: bounds.width, y: bevel))
        ctx.strokePath()

        // Graduations: every millimetre, longer every 5 and 10.
        let ink = UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.85)
        ink.setStroke()
        ctx.setLineWidth(0.5)
        let start = (Ruler.lengthMM - 200) / 2
        let font = UIFont.monospacedDigitSystemFont(ofSize: 2.6 * pointsPerMM, weight: .medium)
        for mm in 0...200 {
            let x = CGFloat(start + Double(mm)) * pointsPerMM
            let length: CGFloat = mm % 10 == 0 ? 4.5 : mm % 5 == 0 ? 3 : 1.8
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: length * pointsPerMM))
            if mm % 10 == 0 {
                let label = "\(mm / 10)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
                let size = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: x - size.width / 2, y: 5 * pointsPerMM), withAttributes: attributes)
            }
        }
        ctx.strokePath()
    }
}
