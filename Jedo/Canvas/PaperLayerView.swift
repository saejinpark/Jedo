import UIKit

/// A soft sheet lying on the paper: a transparent grid sheet with its
/// printed rulings and whatever was drawn on it, or the carbon.
final class PaperLayerView: UIView {
    let sheetID: Int
    private let kind: SheetKind
    private let surfaces: [GraphiteSurface]

    /// Muted green rulings, as on drafting film.
    static let rulingColour = UIColor(red: 0.20, green: 0.50, blue: 0.40, alpha: 1)

    static func colour(_ ink: GridRulings.Ink) -> UIColor {
        switch ink {
        case .green: rulingColour
        // Vermilion, as manuscript paper is printed.
        case .red: UIColor(red: 0.84, green: 0.27, blue: 0.16, alpha: 1)
        // Non-photo blue.
        case .blue: UIColor(red: 0.36, green: 0.66, blue: 0.90, alpha: 1)
        case .black: UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
        }
    }

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
        outline.addLines(between: sheet.outlineMM.map { CGPoint(x: (CGFloat($0.x) + CGFloat(w) / 2) * pt,
                                                                    y: (CGFloat($0.y) + CGFloat(h) / 2) * pt) })
        outline.closeSubpath()

        let body = CAShapeLayer()
        body.path = outline
        body.fillRule = .evenOdd
        switch sheet.kind {
        case .carbon where sheet.carbonInk.isGradient:
            body.fillColor = nil
        case .carbon:
            // Dark but see-through, so the drawing under it still shows faintly. Pitch black was tried and set aside.
            let c = sheet.carbonInk == .navy ? (r: 0.08, g: 0.09, b: 0.16) : Self.coating(sheet.carbonInk.colour(at: 0))
            body.fillColor = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.58).cgColor
        case .grid(.butter):
            // Yellow trace: thin and warm, the drawing under it shows clearly.
            body.fillColor = UIColor(red: 1.0, green: 0.93, blue: 0.64, alpha: 0.30).cgColor
        case .grid:
            // Tracing paper is frosted, not clear: what lies under it dims a little.
            body.fillColor = UIColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 0.36).cgColor
        case .tone:
            // Clear film: only the print shows.
            body.fillColor = UIColor(white: 1, alpha: 0.06).cgColor
        case .photo:
            // Photo paper: opaque, unless it is being used as carbon and laid face down.
            body.fillColor = UIColor(white: 0.98, alpha: sheet.photoCarbon ? 0.2 : 1).cgColor
        }
        layer.addSublayer(body)
        if let photo = sheet.kind.photo {
            let print = CALayer()
            print.contents = PhotoStore.image(photo.id)
            print.contentsGravity = .resize
            // Used as carbon it lies face down: its colours show faintly through the back.
            print.opacity = sheet.photoCarbon ? 0.3 : 1
            layer.addSublayer(print)
        }
        if sheet.kind == .carbon, sheet.carbonInk.isGradient {
            // A coating that runs across the sheet, as it prints.
            let gradient = CAGradientLayer()
            gradient.colors = stride(from: 0.0, through: 1.0, by: 0.125).map { t in
                let c = Self.coating(sheet.carbonInk.colour(at: t))
                return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.62).cgColor
            }
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            let clip = CAShapeLayer()
            clip.path = outline
            clip.fillRule = .evenOdd
            gradient.mask = clip
            layer.addSublayer(gradient)
        }

        if case .tone(let pattern) = sheet.kind {
            let print = CALayer()
            print.contents = Self.tonePrint(pattern, size: bounds.size, pointsPerMM: pt)
            layer.addSublayer(print)
        }

        if case .grid(let pattern) = sheet.kind {
            let rulings = GridRulings.lines(pattern)
            for ink in GridRulings.Ink.allCases {
                for dashed in [false, true] {
                    for weight in GridRulings.Weight.allCases {
                        let path = CGMutablePath()
                        for line in rulings where line.weight == weight && line.ink == ink && line.dashed == dashed {
                            path.move(to: CGPoint(x: line.from.x * pt, y: line.from.y * pt))
                            path.addLine(to: CGPoint(x: line.to.x * pt, y: line.to.y * pt))
                        }
                        if ink == .green, !dashed {
                            for ring in GridRulings.rings(pattern) where ring.weight == weight {
                                let r = CGFloat(ring.radius) * pt
                                path.addEllipse(in: CGRect(x: bounds.midX - r, y: bounds.midY - r, width: 2 * r, height: 2 * r))
                            }
                        }
                        guard !path.isEmpty else { continue }
                        let lines = CAShapeLayer()
                        lines.path = path
                        lines.fillColor = nil
                        lines.strokeColor = Self.colour(ink).withAlphaComponent([0.30, 0.48, 0.66][weight.rawValue]).cgColor
                        lines.lineWidth = [0.35, 0.55, 0.8][weight.rawValue]
                        if dashed { lines.lineDashPattern = [NSNumber(value: Double(pt) * 0.8), NSNumber(value: Double(pt) * 0.8)] }
                        layer.addSublayer(lines)
                    }
                }
            }
        }
        for surface in surfaces { layer.addSublayer(surface.layer) }

        let rim = CAShapeLayer()
        // A piece with a hole is one outline that runs in to the hole and back out the same way:
        // that hairline is not an edge, so it is left out of the rim.
        let corners = sheet.outlineMM.map { CGPoint(x: (CGFloat($0.x) + CGFloat(w) / 2) * pt, y: (CGFloat($0.y) + CGFloat(h) / 2) * pt) }
        let rimPath = CGMutablePath()
        func same(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01 }
        let edges = corners.indices.map { (corners[$0], corners[($0 + 1) % corners.count]) }
        for (a, b) in edges where !same(a, b) && !edges.contains(where: { same($0.0, b) && same($0.1, a) }) {
            rimPath.move(to: a)
            rimPath.addLine(to: b)
        }
        rim.path = rimPath
        self.rimPath = rimPath
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
        } else if sheet.pieceMM != nil {
            // A piece cut from the sheet: its print and drawing end at the cut.
            let clip = CAShapeLayer()
            clip.path = outline
            clip.fillRule = .evenOdd
            clip.frame = bounds
            clip.actions = CanvasView.noAnimations
            layer.mask = clip
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
                    // A row at a time: one path of every dot on the sheet takes seconds to fill.
                    ctx.fillPath()
                }
            }
        }
    }

    /// The prints already drawn: every sheet of one tone is the same print.
    private static var tonePrints: [String: CGImage] = [:]

    private static func tonePrint(_ pattern: TonePattern, size: CGSize, pointsPerMM pt: CGFloat) -> CGImage? {
        let key = "\(pattern) \(Int(size.width.rounded())) \(Int(size.height.rounded())) \(pt)"
        if let made = tonePrints[key] { return made }
        let image = toneImage(pattern, size: size, pointsPerMM: pt)?.cgImage
        tonePrints[key] = image
        return image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A carbon's coating seen on the sheet: the copy colour, deepened.
    static func coating(_ c: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double) {
        (c.r * 0.55, c.g * 0.55, c.b * 0.55)
    }

    private let selectionRim = CAShapeLayer()
    private var rimPath: CGPath?

    /// Marks the sheet picked out with a dashed rim.
    func showSelected(_ selected: Bool) {
        if selectionRim.superlayer == nil, let path = rimPath {
            selectionRim.path = path
            selectionRim.frame = bounds
            selectionRim.fillColor = nil
            selectionRim.strokeColor = UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.75).cgColor
            selectionRim.lineWidth = 1.6
            selectionRim.lineDashPattern = [6, 4]
            selectionRim.actions = CanvasView.noAnimations
            layer.addSublayer(selectionRim)
        }
        selectionRim.isHidden = !selected
    }

    /// Lays the sheet where it is on the paper.
    func place(_ sheet: PaperLayer, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        center = CGPoint(x: sheet.pose.center.x / scale, y: sheet.pose.center.y / scale)
        // Mirrored first, about its own centre, then turned: as `PaperLayer` maps it.
        transform = CGAffineTransform(rotationAngle: sheet.pose.angle)
            .scaledBy(x: sheet.flippedX ? -1 : 1, y: sheet.flippedY ? -1 : 1)
        CATransaction.commit()
    }
}
