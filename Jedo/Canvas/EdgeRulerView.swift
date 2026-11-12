import UIKit

/// A millimetre scale along the top or left edge of the screen, reading the
/// paper beneath: where its edges are, and how far along it the view is.
/// The paper's stretch is light, the desk beyond it darker.
final class EdgeRulerView: UIView {
    enum Side { case top, left }

    let side: Side
    var scale: EdgeScale? { didSet { if scale != oldValue { setNeedsDisplay() } } }

    static let thickness: CGFloat = 22

    init(side: Side) {
        self.side = side
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let horizontal = side == .top
        let depth = horizontal ? bounds.height : bounds.width
        func span(_ from: Double, _ to: Double) -> CGRect {
            horizontal ? CGRect(x: from, y: 0, width: to - from, height: Double(depth))
                : CGRect(x: 0, y: from, width: Double(depth), height: to - from)
        }

        UIColor(red: 0.62, green: 0.60, blue: 0.56, alpha: 0.92).setFill()
        ctx.fill(bounds)
        guard let scale else { return }
        if let paper = scale.paperSpan {
            UIColor(red: 0.975, green: 0.968, blue: 0.945, alpha: 0.96).setFill()
            ctx.fill(span(paper.lowerBound, paper.upperBound))
        }

        let ink = UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
        let font = UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
        let paperRange = 0...Int(scale.paperMM.rounded())
        for tick in scale.ticks {
            let onPaper = paperRange.contains(tick.mm)
            let reach: CGFloat = switch tick.weight {
            case .fine: depth * 0.22
            case .medium: depth * 0.38
            case .bold: depth * 0.6
            }
            ink.withAlphaComponent(onPaper ? 0.75 : 0.4).setFill()
            let at = CGFloat(tick.at)
            // Ticks rise from the inner edge, toward the paper.
            let mark = horizontal ? CGRect(x: at - 0.3, y: depth - reach, width: 0.6, height: reach)
                : CGRect(x: depth - reach, y: at - 0.3, width: reach, height: 0.6)
            ctx.fill(mark)
            guard tick.weight == .bold, onPaper else { continue }
            let label = NSAttributedString(string: "\(tick.mm)", attributes: [.font: font, .foregroundColor: ink.withAlphaComponent(0.8)])
            if horizontal {
                label.draw(at: CGPoint(x: at + 2, y: 1))
            } else {
                ctx.saveGState()
                ctx.translateBy(x: 1, y: at - 2)
                ctx.rotate(by: -.pi / 2)
                label.draw(at: CGPoint(x: 0, y: 0))
                ctx.restoreGState()
            }
        }
        ink.withAlphaComponent(0.25).setFill()
        ctx.fill(horizontal ? CGRect(x: 0, y: depth - 0.5, width: bounds.width, height: 0.5)
                 : CGRect(x: depth - 0.5, y: 0, width: 0.5, height: bounds.height))
    }
}
