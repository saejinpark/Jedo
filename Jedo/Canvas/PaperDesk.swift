import UIKit

/// Holds the sheet the way a desk holds paper: when the iPad turns, the
/// interface turns with it but the sheet does not move under the hand.
///
/// The sheet is a square a few screens across. The screen looks at part of
/// it; the overview map in the corner moves the view. There is no zoom: the
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
    /// Where the sheet's centre sits from the screen's centre, in screen points.
    private var offset = CGPoint.zero

    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        backgroundColor = canvas.backgroundColor
        addSubview(canvas)
        addSubview(minimap)
        minimap.onMove = { [weak self] spot in self?.look(at: spot) }
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
    }

    /// Centres the screen on `spot`, a point of the map as fractions of its side.
    private func look(at spot: CGPoint) {
        offset = Self.clamp(CGPoint(x: -(spot.x - 0.5) * side, y: -(spot.y - 0.5) * side), side: side, screen: bounds.size)
        canvas.center = canvasCenter(in: bounds.size)
        refreshMinimap(drawing: false)
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
/// the screen shows. Touching or dragging in it moves the view there.
final class MinimapView: UIView {
    var onMove: ((CGPoint) -> Void)?
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { follow(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { follow(touches) }

    private func follow(_ touches: Set<UITouch>) {
        guard let touch = touches.first, bounds.width > 0 else { return }
        let p = touch.location(in: self)
        onMove?(CGPoint(x: min(max(p.x / bounds.width, 0), 1), y: min(max(p.y / bounds.height, 0), 1)))
    }
}
