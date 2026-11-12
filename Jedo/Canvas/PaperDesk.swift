import UIKit

/// Holds the sheet the way a desk holds paper: when the iPad turns, the
/// interface turns with it but the sheet does not move under the hand.
///
/// The sheet is a square a few screens across. The screen looks at part of
/// it. The overview map in the corner, and the stick under it, move the view
/// smoothly: the map glides to where it is touched or dragged, the stick pans
/// steadily for as long as it is pushed. There is no zoom: the
/// paper is always at its real size. On every interface rotation the sheet
/// is turned back by the same quarter turn, inside the same animation, so on
/// the glass it stays exactly where it was.
final class PaperDeskController: UIViewController {
    let canvas = CanvasView()
    private var turns = QuarterTurns(0)
    private var desk: PaperDeskView { view as! PaperDeskView }

    override func loadView() {
        view = PaperDeskView(canvas: canvas)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let interfaceTurn = QuarterTurns(approximating: coordinator.targetTransform)
        guard interfaceTurn.count != 0 else { return }
        turns = turns + -interfaceTurn
        desk.turnView(by: -interfaceTurn)
        let target = turns.transform
        coordinator.animate(alongsideTransition: { [canvas, desk] _ in
            canvas.transform = target
            canvas.center = desk.canvasCenter(in: size)
        }, completion: { [desk] _ in
            desk.refreshMinimap(drawing: true)
        })
    }
}

final class PaperDeskView: UIView {
    let canvas: CanvasView
    let minimap = MinimapView()
    let stick = PanStick()
    /// Where the sheet's centre sits from the screen's centre, in screen points.
    private var offset = CGPoint.zero
    /// Where the map asked the view to go; the view glides there.
    private var target: CGPoint?
    /// How the stick is pushed, −1…1 each way.
    private var push = CGVector.zero
    private var ticker: CADisplayLink?

    /// Time for the glide to cover about two thirds of the way.
    static let glideTime = 0.14
    /// Points per second with the stick pushed all the way.
    static let stickSpeed = 700.0

    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        backgroundColor = canvas.backgroundColor
        addSubview(canvas)
        addSubview(minimap)
        addSubview(stick)
        minimap.onMove = { [weak self] spot in self?.glide(to: spot) }
        stick.onPush = { [weak self] push in self?.pan(push) }
        canvas.onOverviewChange = { [weak self] in self?.refreshMinimap(drawing: true) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var side: CGFloat { canvas.sideInPoints ?? max(bounds.width, bounds.height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Bounds and centre, never frame: the canvas may be turned.
        canvas.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        canvas.center = canvasCenter(in: bounds.size)
        let inset = max(safeAreaInsets.top, 20)
        minimap.frame = CGRect(x: max(safeAreaInsets.left, 20), y: inset, width: Self.minimapSide, height: Self.minimapSide)
        stick.frame = CGRect(x: minimap.frame.midX - PanStick.side / 2, y: minimap.frame.maxY + 14,
                             width: PanStick.side, height: PanStick.side)
        refreshMinimap(drawing: minimap.drawing == nil)
    }

    static let minimapSide: CGFloat = 150

    /// The sheet's centre on a screen of `size`, kept so the sheet covers the screen.
    func canvasCenter(in size: CGSize) -> CGPoint {
        offset = Self.clamp(offset, side: side, screen: size)
        return CGPoint(x: size.width / 2 + offset.x, y: size.height / 2 + offset.y)
    }

    static func clamp(_ offset: CGPoint, side: CGFloat, screen: CGSize) -> CGPoint {
        let spareX = max((side - screen.width) / 2, 0), spareY = max((side - screen.height) / 2, 0)
        return CGPoint(x: min(max(offset.x, -spareX), spareX), y: min(max(offset.y, -spareY), spareY))
    }

    /// The sheet turns with the device, not the interface, so the view's offset turns too.
    func turnView(by turn: QuarterTurns) {
        offset = offset.applying(turn.transform)
        target = nil
    }

    /// Glides the screen's centre to `spot`, a point of the map as fractions of its side.
    private func glide(to spot: CGPoint) {
        target = Self.clamp(CGPoint(x: -(spot.x - 0.5) * side, y: -(spot.y - 0.5) * side), side: side, screen: bounds.size)
        startTicking()
    }

    private func pan(_ push: CGVector) {
        self.push = push
        if push != .zero {
            target = nil
            startTicking()
        }
    }

    private func startTicking() {
        guard ticker == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        ticker = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(max(link.targetTimestamp - link.timestamp, 1.0 / 240), 1.0 / 20)
        if push != .zero {
            // Gentle near the middle of the stick, quick at its rim.
            let strength = min(hypot(push.dx, push.dy), 1)
            let speed = Self.stickSpeed * pow(strength, 1.6) / max(strength, 1e-6)
            offset.x -= push.dx * speed * dt
            offset.y -= push.dy * speed * dt
        } else if let goal = target {
            let k = 1 - exp(-dt / Self.glideTime)
            offset.x += (goal.x - offset.x) * k
            offset.y += (goal.y - offset.y) * k
            if hypot(goal.x - offset.x, goal.y - offset.y) < 0.3 {
                offset = goal
                target = nil
            }
        }
        canvas.center = canvasCenter(in: bounds.size)
        refreshMinimap(drawing: false)
        if push == .zero, target == nil {
            link.invalidate()
            ticker = nil
        }
    }

    /// Updates the map's view box, and with `drawing` its picture of the sheet and tools.
    func refreshMinimap(drawing: Bool) {
        guard side > 0 else { return }
        let frame = canvas.frame
        minimap.viewport = CGRect(x: (bounds.minX - frame.minX) / side, y: (bounds.minY - frame.minY) / side,
                                  width: bounds.width / side, height: bounds.height / side)
        minimap.sheetTurn = CGAffineTransform(a: canvas.transform.a, b: canvas.transform.b,
                                              c: canvas.transform.c, d: canvas.transform.d, tx: 0, ty: 0)
        if drawing {
            minimap.drawing = canvas.overviewImage(size: Self.overviewCells)
            minimap.tools = canvas.toolOutlines
        }
        minimap.setNeedsDisplay()
    }

    static let overviewCells = 200
}

/// The whole sheet in a corner: the drawing, the tools, and a box for what
/// the screen shows. Dragging the box moves it from where it was taken hold
/// of; touching elsewhere sends it there. The desk glides the view after it.
final class MinimapView: UIView {
    /// Where the screen's centre should go, as fractions of the map.
    var onMove: ((CGPoint) -> Void)?
    /// Where in the box the finger took hold, from the box's centre, as fractions.
    private var hold = CGPoint.zero
    /// What the screen shows, as fractions of the map.
    var viewport = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// How the sheet is turned on screen.
    var sheetTurn = CGAffineTransform.identity
    var drawing: CGImage?
    /// Tool outlines, as fractions of the sheet in its own orientation.
    var tools: [[CGPoint]] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        accessibilityLabel = "전체 용지 지도"
        accessibilityHint = "끌어서 보는 곳을 옮깁니다"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let side = bounds.width
        let frame = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10)
        UIColor(red: 0.965, green: 0.955, blue: 0.925, alpha: 1).setFill()
        frame.fill()
        ctx.saveGState()
        frame.addClip()

        // The sheet in its own orientation, turned as it lies on screen.
        ctx.saveGState()
        ctx.translateBy(x: side / 2, y: side / 2)
        ctx.concatenate(sheetTurn)
        ctx.translateBy(x: -side / 2, y: -side / 2)
        if let drawing {
            ctx.interpolationQuality = .medium
            UIImage(cgImage: drawing).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        UIColor(red: 0.35, green: 0.45, blue: 0.50, alpha: 0.6).setStroke()
        for outline in tools where outline.count > 1 {
            let path = UIBezierPath()
            for (i, p) in outline.enumerated() {
                let q = CGPoint(x: p.x * side, y: p.y * side)
                i == 0 ? path.move(to: q) : path.addLine(to: q)
            }
            path.close()
            path.lineWidth = 0.8
            path.stroke()
        }
        ctx.restoreGState()

        // What the screen shows.
        let box = CGRect(x: viewport.minX * side, y: viewport.minY * side, width: viewport.width * side, height: viewport.height * side)
        let viewPath = UIBezierPath(roundedRect: box, cornerRadius: 2)
        UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.07).setFill()
        viewPath.fill()
        UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.75).setStroke()
        viewPath.lineWidth = 1.5
        viewPath.stroke()
        ctx.restoreGState()

        UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.15).setStroke()
        frame.lineWidth = 1
        frame.stroke()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, bounds.width > 0 else { return }
        let p = fraction(touch)
        hold = viewport.contains(p) ? CGPoint(x: p.x - viewport.midX, y: p.y - viewport.midY) : .zero
        follow(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { follow(touches) }

    private func fraction(_ touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: p.x / bounds.width, y: p.y / bounds.height)
    }

    private func follow(_ touches: Set<UITouch>) {
        guard let touch = touches.first, bounds.width > 0 else { return }
        let p = fraction(touch)
        onMove?(CGPoint(x: min(max(p.x - hold.x, 0), 1), y: min(max(p.y - hold.y, 0), 1)))
    }
}

/// A thumb stick for moving the view: push the knob and the view pans that
/// way, slowly near the middle and faster toward the rim; let go and it stops.
final class PanStick: UIView {
    static let side: CGFloat = 96
    /// How the knob is pushed, −1…1 each way; zero when let go.
    var onPush: ((CGVector) -> Void)?
    private var knob = CGVector.zero
    private var finger: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        accessibilityLabel = "화면 이동 조이스틱"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var reach: CGFloat { bounds.width / 2 - 20 }

    override func draw(_ rect: CGRect) {
        let ink = UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
        let base = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        UIColor(red: 0.965, green: 0.955, blue: 0.925, alpha: 0.92).setFill()
        base.fill()
        ink.withAlphaComponent(0.15).setStroke()
        base.lineWidth = 1
        base.stroke()
        // Four small arrows round the rim.
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = bounds.width / 2 - 9
        ink.withAlphaComponent(0.35).setFill()
        for k in 0..<4 {
            let a = CGFloat(k) * .pi / 2
            let tip = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            let back = CGPoint(x: c.x + cos(a) * (r - 6), y: c.y + sin(a) * (r - 6))
            let side = CGVector(dx: -sin(a) * 4, dy: cos(a) * 4)
            let arrow = UIBezierPath()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: back.x + side.dx, y: back.y + side.dy))
            arrow.addLine(to: CGPoint(x: back.x - side.dx, y: back.y - side.dy))
            arrow.close()
            arrow.fill()
        }
        let knobCentre = CGPoint(x: c.x + knob.dx * reach, y: c.y + knob.dy * reach)
        let knobPath = UIBezierPath(ovalIn: CGRect(x: knobCentre.x - 17, y: knobCentre.y - 17, width: 34, height: 34))
        ink.withAlphaComponent(finger == nil ? 0.55 : 0.8).setFill()
        knobPath.fill()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard finger == nil, let touch = touches.first else { return }
        finger = touch
        follow(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let finger, touches.contains(finger) else { return }
        follow(finger)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { letGo(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { letGo(touches) }

    private func follow(_ touch: UITouch) {
        let p = touch.location(in: self)
        var v = CGVector(dx: (p.x - bounds.midX) / reach, dy: (p.y - bounds.midY) / reach)
        let length = hypot(v.dx, v.dy)
        if length > 1 { v = CGVector(dx: v.dx / length, dy: v.dy / length) }
        // A small dead zone, so resting a thumb on it doesn't drift.
        let push = length < 0.12 ? CGVector.zero : v
        knob = v
        setNeedsDisplay()
        onPush?(push)
    }

    private func letGo(_ touches: Set<UITouch>) {
        guard let finger, touches.contains(finger) else { return }
        self.finger = nil
        knob = .zero
        setNeedsDisplay()
        onPush?(.zero)
    }
}
