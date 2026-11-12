import UIKit

/// A smoky-grey acrylic drafting ruler: graduations along both long edges, a
/// 5 mm grid across its body, and a bevelled lower edge. It only shows the ruler; the canvas handles touches.
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

        // Clear smoky-grey acrylic.
        UIColor(red: 0.80, green: 0.80, blue: 0.79, alpha: 0.32).setFill()
        body.fill()

        // Bevel along the lower edge.
        let bevel = bounds.height - 2.2 * pointsPerMM
        UIColor(red: 0.62, green: 0.62, blue: 0.61, alpha: 0.22).setFill()
        UIRectFillUsingBlendMode(CGRect(x: 0, y: bevel, width: bounds.width, height: bounds.height - bevel), .normal)

        UIColor(red: 0.36, green: 0.36, blue: 0.36, alpha: 0.55).setStroke()
        body.lineWidth = 0.6
        body.stroke()
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: 0, y: bevel))
        ctx.addLine(to: CGPoint(x: bounds.width, y: bevel))
        ctx.strokePath()

        let ink = UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.85)
        let start = (Ruler.lengthMM - 200) / 2
        let mm = pointsPerMM

        // A grid across the body, every 5 mm, stronger every centimetre, as on a
        // clear pattern-drafting ruler: for parallels and seam allowances.
        let gridTop = 7.5 * mm, gridBottom = bounds.height - 2.2 * mm
        for (step, alpha, width) in [(5, 0.16, 0.4), (10, 0.30, 0.55)] as [(Int, CGFloat, CGFloat)] {
            ink.withAlphaComponent(alpha).setStroke()
            ctx.setLineWidth(width)
            for along in stride(from: 0, through: 200, by: step) where step == 10 || along % 10 != 0 {
                let x = CGFloat(start + Double(along)) * mm
                ctx.move(to: CGPoint(x: x, y: gridTop))
                ctx.addLine(to: CGPoint(x: x, y: gridBottom))
            }
            for across in stride(from: 10, to: Int(Ruler.widthMM) - 2, by: 5) where (across % 10 == 0) == (step == 10) {
                let y = CGFloat(across) * mm
                ctx.move(to: CGPoint(x: CGFloat(start) * mm, y: y))
                ctx.addLine(to: CGPoint(x: CGFloat(start + 200) * mm, y: y))
            }
            ctx.strokePath()
        }

        // Graduations along both long edges: every millimetre, longer every 5 and 10.
        ink.setStroke()
        ctx.setLineWidth(0.5)
        let font = UIFont.monospacedDigitSystemFont(ofSize: 2.6 * mm, weight: .medium)
        let small = UIFont.monospacedDigitSystemFont(ofSize: 2.0 * mm, weight: .regular)
        for tick in 0...200 {
            let x = CGFloat(start + Double(tick)) * mm
            let length: CGFloat = tick % 10 == 0 ? 4.5 : tick % 5 == 0 ? 3 : 1.8
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: length * mm))
            // Along the bevelled lower edge, shorter, reading the same way.
            let lower = min(length, 2.2) * mm
            ctx.move(to: CGPoint(x: x, y: bounds.height))
            ctx.addLine(to: CGPoint(x: x, y: bounds.height - lower))
            if tick % 10 == 0 {
                let label = "\(tick / 10)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
                let size = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: x - size.width / 2, y: 4.8 * mm), withAttributes: attributes)
                let lowerLabel = "\(tick / 10)" as NSString
                let lowerAttributes: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: ink.withAlphaComponent(0.7)]
                let lowerSize = lowerLabel.size(withAttributes: lowerAttributes)
                if tick > 0 && tick < 200 {
                    lowerLabel.draw(at: CGPoint(x: x + 0.6 * mm, y: bounds.height - 2.2 * mm - lowerSize.height - 0.2 * mm),
                                    withAttributes: lowerAttributes)
                }
            }
        }
        ctx.strokePath()
    }
}
