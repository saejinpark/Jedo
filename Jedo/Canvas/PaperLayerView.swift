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
            // Dark but see-through, so the drawing under it still shows faintly. Pitch black was tried and set aside.
            body.fillColor = UIColor(red: 0.08, green: 0.09, blue: 0.16, alpha: 0.58).cgColor
        case .grid(.butter):
            // Yellow trace: thin and warm, the drawing under it shows clearly.
            body.fillColor = UIColor(red: 1.0, green: 0.93, blue: 0.64, alpha: 0.30).cgColor
        case .grid:
            // Tracing paper is frosted, not clear: what lies under it dims a little.
            body.fillColor = UIColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 0.36).cgColor
        case .tone:
            // Clear film: only the print shows.
            body.fillColor = UIColor(white: 1, alpha: 0.06).cgColor
        }
        layer.addSublayer(body)

        if case .tone(let pattern) = sheet.kind {
            let print = CALayer()
            print.contents = Self.toneImage(pattern, size: bounds.size, pointsPerMM: pt)?.cgImage
            layer.addSublayer(print)
        }

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
        if sheet.kind.isTone {
            // What the knife has left: the whole sheet, its film and print, is masked to it.
            toneMask.frame = bounds
            toneMask.magnificationFilter = .linear
            toneMask.actions = CanvasView.noAnimations
            layer.mask = toneMask
        }
    }

    private let toneMask = CALayer()

    /// Shows what is left of a sheet of tone after cutting and peeling.
    /// Cuts show as hairline gaps.
    func showTone(_ cut: ToneCut) {
        // White with the cells as its alpha: a layer mask reads only the alpha.
        let count = cut.columns * cut.rows
        var pixels = [UInt32](repeating: 0, count: count)
        for i in 0..<count where cut.shows(i) { pixels[i] = 0xFFFF_FFFF }
        guard let image = CanvasView.makeImage(pixels: pixels, width: cut.columns, height: cut.rows) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The grid may run a little past the sheet; stretch so cells keep their size.
        let pt = bounds.width / CGFloat(Double(kind.sizeMM.width) / ToneCut.cellMM)
        toneMask.frame = CGRect(x: 0, y: 0, width: CGFloat(cut.columns) * pt, height: CGFloat(cut.rows) * pt)
        toneMask.contents = image
        CATransaction.commit()
    }

    /// The print of a sheet of tone: round black dots on a square grid at
    /// 45°, the classic screen, or ruled lines.
    private static func toneImage(_ pattern: TonePattern, size: CGSize, pointsPerMM pt: CGFloat) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let ink = UIColor(white: 0.08, alpha: 1)
        let widthMM = Double(size.width / pt), heightMM = Double(size.height / pt)
        return UIGraphicsImageRenderer(size: size).image { context in
            let ctx = context.cgContext
            ink.setFill()
            ink.setStroke()
            let pitch = TonePattern.pitchMM
            switch pattern {
            case .lines:
                ctx.setLineWidth(CGFloat(TonePattern.lineWidthMM) * pt)
                // Lines at 45°: x + y = k·pitch·√2.
                let step = pitch * 2.0.squareRoot()
                var k = 0.0
                while k <= widthMM + heightMM {
                    ctx.move(to: CGPoint(x: CGFloat(k) * pt, y: 0))
                    ctx.addLine(to: CGPoint(x: CGFloat(k - heightMM) * pt, y: CGFloat(heightMM) * pt))
                    k += step
                }
                ctx.strokePath()
            default:
                // Dots on a grid turned 45°, as screen tone is printed.
                let diagonal = (widthMM * widthMM + heightMM * heightMM).squareRoot()
                let n = Int((diagonal / pitch).rounded(.up))
                let c = cos(Double.pi / 4), s = sin(Double.pi / 4)
                let centre = (x: widthMM / 2, y: heightMM / 2)
                for i in -n...n {
                    for j in -n...n {
                        let u = Double(i) * pitch, v = Double(j) * pitch
                        let x = centre.x + u * c - v * s, y = centre.y + u * s + v * c
                        guard x > -pitch, y > -pitch, x < widthMM + pitch, y < heightMM + pitch else { continue }
                        let r = TonePattern.dotRadius(coverage: pattern.coverage(atX: x, width: widthMM))
                        ctx.addEllipse(in: CGRect(x: CGFloat(x - r) * pt, y: CGFloat(y - r) * pt,
                                                  width: CGFloat(2 * r) * pt, height: CGFloat(2 * r) * pt))
                    }
                }
                ctx.fillPath()
            }
        }
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
