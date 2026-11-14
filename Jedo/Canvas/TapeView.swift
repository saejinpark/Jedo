import UIKit

/// The tape measure pulled out between two fingertips: a soft tape graduated in
/// millimetres from its tab, running on a little past the far finger, with a
/// red hairline where that finger holds it. The length is read off the tape.
final class TapeView: UIView {
    /// Width of the tape.
    static let widthMM = 14.0
    /// How far the tape runs before its zero (the tab) and past the far end.
    static let tabMM = 3.0, tailMM = 16.0

    private var lengthMM = 0.0
    private var pointsPerMM: CGFloat = 5

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays the tape from `a` to `b`, in the canvas's points.
    func show(from a: CGPoint, to b: CGPoint, pointsPerMM pt: CGFloat) {
        let length = hypot(b.x - a.x, b.y - a.y)
        lengthMM = Double(length / pt)
        pointsPerMM = pt
        let before = CGFloat(Self.tabMM) * pt, after = CGFloat(Self.tailMM) * pt
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transform = .identity
        bounds = CGRect(x: 0, y: 0, width: before + length + after, height: CGFloat(Self.widthMM) * pt)
        // The zero sits on `a`; the tape lies to one side of the line measured, its graduated edge on it.
        let angle = atan2(b.y - a.y, b.x - a.x)
        let along = (before + length + after) / 2 - before, across = bounds.height / 2
        center = CGPoint(x: a.x + cos(angle) * along - sin(angle) * across, y: a.y + sin(angle) * along + cos(angle) * across)
        transform = CGAffineTransform(rotationAngle: angle)
        CATransaction.commit()
        isHidden = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let pt = pointsPerMM, zero = CGFloat(Self.tabMM) * pt
        // The tape: cream cloth with a darker edge.
        ctx.setFillColor(UIColor(red: 0.99, green: 0.95, blue: 0.74, alpha: 0.94).cgColor)
        ctx.fill(bounds)
        ctx.setStrokeColor(UIColor(red: 0.45, green: 0.38, blue: 0.16, alpha: 0.8).cgColor)
        ctx.setLineWidth(0.8)
        ctx.stroke(bounds.insetBy(dx: 0.4, dy: 0.4))
        // The metal tab at its start.
        ctx.setFillColor(UIColor(white: 0.72, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: zero, height: bounds.height))
        // Graduations along the edge on the measured line: every millimetre, longer at 5 and 10.
        let ink = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        ctx.setStrokeColor(ink.cgColor)
        let last = Int((lengthMM + Self.tailMM).rounded(.down))
        let font = UIFont.monospacedDigitSystemFont(ofSize: max(2.8 * pt, 6), weight: .medium)
        for mm in 0...max(last, 0) {
            let x = zero + CGFloat(mm) * pt
            let tall: CGFloat = mm % 10 == 0 ? 5.5 : mm % 5 == 0 ? 4 : 2.5
            ctx.setLineWidth(mm % 10 == 0 ? 1 : 0.6)
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: tall * pt))
            ctx.strokePath()
            if mm % 10 == 0, mm > 0 {
                let text = NSAttributedString(string: "\(mm / 10)", attributes: [.font: font, .foregroundColor: ink])
                let size = text.size()
                text.draw(at: CGPoint(x: x - size.width / 2, y: 6.5 * pt))
            }
        }
        // The red hairline at the far fingertip: read the tape here.
        let end = zero + CGFloat(lengthMM) * pt
        ctx.setStrokeColor(UIColor(red: 0.80, green: 0.12, blue: 0.10, alpha: 0.95).cgColor)
        ctx.setLineWidth(1.2)
        ctx.move(to: CGPoint(x: end, y: 0))
        ctx.addLine(to: CGPoint(x: end, y: bounds.height))
        ctx.strokePath()
    }
}
