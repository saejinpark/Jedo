import UIKit

/// Pushpins standing in the board at vanishing points: a round head above
/// everything, and the point where the shaft goes in, which the tools rest
/// against, marked by a fine cross.
final class PinsView: UIView {
    /// Radius of a pin's head.
    static let headMM = 3.0

    private var pins: [CGPoint] = []
    private var headRadius: CGFloat = 15

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ pins: [CGPoint], headRadius: CGFloat) {
        self.pins = pins
        self.headRadius = headRadius
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        for p in pins {
            let r = headRadius
            let head = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
            // Shadow on the board, a little down and right.
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.18).cgColor)
            ctx.fillEllipse(in: head.offsetBy(dx: r * 0.25, dy: r * 0.35))
            // The head: lacquered red, see-through enough to show the point.
            ctx.setFillColor(UIColor(red: 0.72, green: 0.16, blue: 0.13, alpha: 0.78).cgColor)
            ctx.fillEllipse(in: head)
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.45).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - r * 0.55, y: p.y - r * 0.6, width: r * 0.55, height: r * 0.45))
            // Where it goes in.
            ctx.setStrokeColor(UIColor(white: 0.08, alpha: 0.9).cgColor)
            ctx.setLineWidth(0.6)
            ctx.move(to: CGPoint(x: p.x - r * 0.45, y: p.y)); ctx.addLine(to: CGPoint(x: p.x + r * 0.45, y: p.y))
            ctx.move(to: CGPoint(x: p.x, y: p.y - r * 0.45)); ctx.addLine(to: CGPoint(x: p.x, y: p.y + r * 0.45))
            ctx.strokePath()
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        hypot(Double(x - other.x), Double(y - other.y))
    }
}
