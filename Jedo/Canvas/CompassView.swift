import UIKit

/// A steel drafting compass seen from above: the needle leg, the lead leg and
/// the knurled handle where they meet. It only shows the compass; the canvas
/// handles touches. It covers the whole canvas and draws in its coordinates.
final class CompassView: UIView {
    private let shadowLayer = CAShapeLayer()
    private let legsLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let needleLayer = CAShapeLayer()
    private let leadLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        isHidden = true
        accessibilityLabel = "컴퍼스"

        shadowLayer.fillColor = UIColor.black.withAlphaComponent(0.13).cgColor
        legsLayer.fillColor = UIColor(red: 0.66, green: 0.69, blue: 0.72, alpha: 0.96).cgColor
        legsLayer.strokeColor = UIColor(red: 0.32, green: 0.35, blue: 0.39, alpha: 0.9).cgColor
        legsLayer.lineWidth = 0.6
        handleLayer.fillColor = UIColor(red: 0.42, green: 0.45, blue: 0.49, alpha: 0.97).cgColor
        handleLayer.strokeColor = UIColor(red: 0.22, green: 0.24, blue: 0.27, alpha: 0.9).cgColor
        handleLayer.lineWidth = 0.6
        needleLayer.fillColor = UIColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 1).cgColor
        needleLayer.strokeColor = UIColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 0.7).cgColor
        needleLayer.lineWidth = 0.8
        leadLayer.fillColor = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1).cgColor
        for sublayer in [shadowLayer, legsLayer, needleLayer, leadLayer, handleLayer] {
            sublayer.actions = ["path": NSNull(), "hidden": NSNull()]
            layer.addSublayer(sublayer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func hide() { isHidden = true }

    /// Draws the compass. Canvas pixels in, points out.
    func show(_ compass: Compass, scale: CGFloat, pixelsPerMillimeter: Double) {
        let mm = CGFloat(pixelsPerMillimeter) / scale
        let needle = CGPoint(x: compass.needle.x / scale, y: compass.needle.y / scale)
        let lead = compass.lead.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }

        let legs = UIBezierPath()
        let handle = UIBezierPath()
        let hinge: CGPoint
        if let lead, hypot(lead.x - needle.x, lead.y - needle.y) > 0.5 {
            hinge = CGPoint(x: (needle.x + lead.x) / 2, y: (needle.y + lead.y) / 2)
            legs.append(Self.leg(from: hinge, to: needle, root: 1.7 * mm, tip: 0.35 * mm))
            legs.append(Self.leg(from: hinge, to: lead, root: 1.7 * mm, tip: 0.9 * mm))
        } else {
            hinge = needle // legs closed, standing on the needle
        }
        handle.append(UIBezierPath(ovalIn: CGRect(x: hinge.x - 2.6 * mm, y: hinge.y - 2.6 * mm, width: 5.2 * mm, height: 5.2 * mm)))
        // The knurled grip on top of the handle.
        let grip = UIBezierPath(ovalIn: CGRect(x: hinge.x - 1.1 * mm, y: hinge.y - 1.1 * mm, width: 2.2 * mm, height: 2.2 * mm))

        let point = UIBezierPath(ovalIn: CGRect(x: needle.x - 0.35 * mm, y: needle.y - 0.35 * mm, width: 0.7 * mm, height: 0.7 * mm))
        let ring = UIBezierPath(ovalIn: CGRect(x: needle.x - 1.4 * mm, y: needle.y - 1.4 * mm, width: 2.8 * mm, height: 2.8 * mm))
        let needlePath = UIBezierPath()
        needlePath.append(point)
        needlePath.append(ring)

        let shadow = UIBezierPath()
        shadow.append(legs)
        shadow.append(handle)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.path = shadow.cgPath
        shadowLayer.setAffineTransform(CGAffineTransform(translationX: 1.2 * mm, y: 1.6 * mm))
        legsLayer.path = legs.cgPath
        handle.append(grip.reversing())
        handleLayer.path = handle.cgPath
        needleLayer.path = needlePath.cgPath
        needleLayer.fillRule = .evenOdd
        leadLayer.path = lead.map {
            UIBezierPath(ovalIn: CGRect(x: $0.x - 0.45 * mm, y: $0.y - 0.45 * mm, width: 0.9 * mm, height: 0.9 * mm)).cgPath
        }
        CATransaction.commit()
        isHidden = false
    }

    /// A leg tapering from `root` wide at the hinge to `tip` wide at its point.
    private static func leg(from hinge: CGPoint, to end: CGPoint, root: CGFloat, tip: CGFloat) -> UIBezierPath {
        let dx = end.x - hinge.x, dy = end.y - hinge.y
        let length = max(hypot(dx, dy), 0.001)
        let nx = -dy / length, ny = dx / length
        let path = UIBezierPath()
        path.move(to: CGPoint(x: hinge.x + nx * root / 2, y: hinge.y + ny * root / 2))
        path.addLine(to: CGPoint(x: end.x + nx * tip / 2, y: end.y + ny * tip / 2))
        path.addLine(to: CGPoint(x: end.x - nx * tip / 2, y: end.y - ny * tip / 2))
        path.addLine(to: CGPoint(x: hinge.x - nx * root / 2, y: hinge.y - ny * root / 2))
        path.close()
        return path
    }
}
