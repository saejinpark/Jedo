import UIKit

/// The tape measure pulled out between two fingertips: a soft tape graduated in
/// millimetres from its tab, running on a little past the far finger, with a
/// red hairline there. The length is read off the tape. The fingers hold its
/// near edge; the graduations run along its far edge, clear of them.
final class TapeView: UIView {
    /// Width of the tape.
    static let widthMM = 24.0
    /// How far the tape runs before its zero (the tab) and past the far end.
    static let tabMM = 3.0, tailMM = 16.0

    private var lengthMM = 0.0
    /// Graduated in inches and sixteenths instead of centimetres and millimetres.
    var inches = false { didSet { setNeedsDisplay() } }
    private var pointsPerMM: CGFloat = 5
    /// Which way the body lies from the edge the fingers hold, in the view's own y: +1 down from its top edge, −1 up from its bottom edge.
    private var side: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays the tape from `a` to `b`, in the canvas's points, its body toward `up` (a direction on the canvas).
    func show(from a: CGPoint, to b: CGPoint, pointsPerMM pt: CGFloat, up: CGVector) {
        let length = hypot(b.x - a.x, b.y - a.y)
        lengthMM = Double(length / pt)
        pointsPerMM = pt
        let before = CGFloat(Self.tabMM) * pt, after = CGFloat(Self.tailMM) * pt
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transform = .identity
        bounds = CGRect(x: 0, y: 0, width: before + length + after, height: CGFloat(Self.widthMM) * pt)
        // The zero sits level with `a`; the fingers' line is one edge of the tape, and its body lies away from them.
        // A tape not yet pulled out lies level, reading left to right.
        let angle = length > 0.5 ? atan2(b.y - a.y, b.x - a.x) : atan2(-up.dx, up.dy)
        side = -sin(angle) * up.dx + cos(angle) * up.dy >= 0 ? 1 : -1
        let along = (before + length + after) / 2 - before, across = side * bounds.height / 2
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
        // The graduated edge is the one away from the fingers; the figures stand upright as the tape is held.
        let edge: CGFloat = side > 0 ? bounds.height : 0, inward: CGFloat = -side
        // One graduation: its place along the tape in millimetres, how tall, how heavy, and its figure if it has one.
        func mark(_ at: Double, tall: CGFloat, heavy: Bool, figure: String?) {
            let x = zero + CGFloat(at) * pt
            ctx.setLineWidth(heavy ? 1 : 0.6)
            ctx.move(to: CGPoint(x: x, y: edge))
            ctx.addLine(to: CGPoint(x: x, y: edge + inward * tall * pt))
            ctx.strokePath()
            guard let figure else { return }
            let text = NSAttributedString(string: figure, attributes: [.font: font, .foregroundColor: ink])
            let size = text.size()
            ctx.saveGState()
            ctx.translateBy(x: x, y: edge + inward * 8.6 * pt)
            if side > 0 { ctx.rotate(by: .pi) }
            text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
            ctx.restoreGState()
        }
        if inches {
            // Sixteenths of an inch: taller at the eighth, quarter, half and whole.
            let sixteenth = 25.4 / 16
            for k in 0...max(Int(Double(last) / sixteenth), 0) {
                let tall: CGFloat = k % 16 == 0 ? 5.5 : k % 8 == 0 ? 4.6 : k % 4 == 0 ? 3.6 : k % 2 == 0 ? 2.7 : 1.9
                mark(Double(k) * sixteenth, tall: tall, heavy: k % 16 == 0, figure: k % 16 == 0 && k > 0 ? "\(k / 16)" : nil)
            }
        } else {
            for mm in 0...max(last, 0) {
                mark(Double(mm), tall: mm % 10 == 0 ? 5.5 : mm % 5 == 0 ? 4 : 2.5, heavy: mm % 10 == 0,
                     figure: mm % 10 == 0 && mm > 0 ? "\(mm / 10)" : nil)
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
