import UIKit

/// A soft sheet lying on the paper: a transparent grid sheet with its
/// printed rulings and whatever was drawn on it, or the carbon.
final class PaperLayerView: UIView {
    let sheetID: Int
    private let kind: SheetKind
    private let surfaces: [GraphiteSurface]

    /// Muted green rulings, as on drafting film.
    static let rulingColour = UIColor(red: 0.20, green: 0.50, blue: 0.40, alpha: 1)

    /// `surfaces` are what is drawn on the sheet, bottom first.
    init(layer sheet: PaperLayer, surfaces: [GraphiteSurface], scale: CGFloat, pixelsPerMillimeter ppmm: Double) {
        sheetID = sheet.id
        kind = sheet.kind
        self.surfaces = surfaces
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isOpaque = false
        let pt = CGFloat(ppmm) / scale // points per millimetre
        let (w, h) = sheet.kind.sizeMM
        bounds = CGRect(x: 0, y: 0, width: CGFloat(w) * pt, height: CGFloat(h) * pt)

        let outline = CGMutablePath()
        outline.addLines(between: sheet.kind.outlineMM.map { CGPoint(x: (CGFloat($0.x) + CGFloat(w) / 2) * pt,
                                                                    y: (CGFloat($0.y) + CGFloat(h) / 2) * pt) })
        outline.closeSubpath()

        let body = CAShapeLayer()
        body.path = outline
        switch sheet.kind {
        case .carbon:
            // Pitch black and opaque, as carbon paper is: what it copies shows once it is moved or hidden.
            body.fillColor = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1).cgColor
        case .grid:
            body.fillColor = UIColor(white: 1, alpha: 0.30).cgColor
        }
        layer.addSublayer(body)

        if case .grid(let pattern) = sheet.kind {
            for weight in GridRulings.Weight.allCases {
                let path = CGMutablePath()
                for line in GridRulings.lines(pattern) where line.weight == weight {
                    path.move(to: CGPoint(x: line.from.x * pt, y: line.from.y * pt))
                    path.addLine(to: CGPoint(x: line.to.x * pt, y: line.to.y * pt))
                }
                for ring in GridRulings.rings(pattern) where ring.weight == weight {
                    let r = CGFloat(ring.radius) * pt
                    path.addEllipse(in: CGRect(x: bounds.midX - r, y: bounds.midY - r, width: 2 * r, height: 2 * r))
                }
                let lines = CAShapeLayer()
                lines.path = path
                lines.fillColor = nil
                lines.strokeColor = Self.rulingColour.withAlphaComponent([0.30, 0.48, 0.66][weight.rawValue]).cgColor
                lines.lineWidth = [0.35, 0.55, 0.8][weight.rawValue]
                layer.addSublayer(lines)
            }
        }
        for surface in surfaces { layer.addSublayer(surface.layer) }

        let rim = CAShapeLayer()
        rim.path = outline
        rim.fillColor = nil
        rim.strokeColor = UIColor(white: 0.30, alpha: 0.45).cgColor
        rim.lineWidth = 0.7
        layer.addSublayer(rim)
        layer.sublayers?.forEach { $0.actions = CanvasView.noAnimations; $0.frame = bounds }
        for surface in surfaces { surface.layer.frame = bounds }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays the sheet where it is on the paper.
    func place(_ sheet: PaperLayer, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        center = CGPoint(x: sheet.pose.center.x / scale, y: sheet.pose.center.y / scale)
        transform = CGAffineTransform(rotationAngle: sheet.pose.angle)
        CATransaction.commit()
    }
}
