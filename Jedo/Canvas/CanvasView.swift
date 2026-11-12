import UIKit

/// The sheet of paper on screen. Apple Pencil draws; fingers hold the tools.
///
/// Paper is a grid of layers sharing one texture image. Graphite sits above
/// it in 128-pixel tiles that are created when first drawn on and redrawn
/// only where they changed. Tools lie on top, in the paper's own coordinates,
/// so they turn with the paper.
final class CanvasView: UIView {
    /// Read at the start of every stroke, so a lead picked a moment ago is always the one used.
    var currentGrade: () -> PencilGrade = { .hb }
    /// Called after every change to what can be undone or redone.
    var onHistoryChange: ((_ canUndo: Bool, _ canRedo: Bool) -> Void)?
    /// Called when the drawing or the tools change, for the overview map.
    var onOverviewChange: (() -> Void)?
    /// Called when a finger taps or rubs the paper away from any tool, as if trying to draw.
    var onFingerTouch: (() -> Void)?
    /// How the compass is handled; changing it pulls the needle out.
    var compassStyle: CompassStyle = .firstDraft {
        didSet {
            guard compassStyle != oldValue else { return }
            keptSpread = nil
            pullNeedle()
        }
    }

    /// Whether the hand holds the eraser, so a finger rubbing the paper erases.
    var eraserInHand = false

    /// Tools lying on the paper, bottom first. Canvas pixels.
    private(set) var tools: [DeskTool] = []
    /// Their bodies, in the same order, for guiding the pencil.
    private var toolShapes: [ToolShape] = []
    private var toolViews: [ToolKind: any ToolDisplay] = [:]
    /// Fingers holding each tool, oldest first, with where each was last (canvas pixels).
    private var holders: [ToolKind: [(touch: UITouch, point: CGPoint)]] = [:]
    /// Tools lying on top of or under a tool when it was picked up: they pass
    /// over each other freely instead of butting.
    private var stacked: [ToolKind: Set<ToolKind>] = [:]
    /// Whether the compass is out, so a finger held still plants its needle.
    private(set) var compassOnDesk = false
    /// The compass while its needle is in the paper. Canvas pixels.
    private(set) var compass: Compass?
    /// Whether the needle is in the paper, so the compass guides the pencil.
    private var needleIn = false
    private let compassView = CompassView()
    /// The finger that planted the needle, while it stays down, and where it was last.
    private var needleFinger: (touch: UITouch, point: CGPoint)?
    /// Until the compass first draws, the planting finger can still nudge the needle.
    private var needleSettled = false
    private var pullNeedleAfterStroke = false
    /// The legs' last spread and lead direction, for the next time the needle goes in.
    private var keptSpread: (spread: Double, angle: Double)?
    /// Fingers that might be held still to plant the needle.
    private var presses = LongPress<UITouch>(slop: 20)

    private var guide: StrokeGuide?
    private let inkLayer = CALayer()
    /// Graph-paper rulings, printed on the paper: under the graphite, never erased.
    private let gridLayer = CALayer()

    private(set) var sheet: DraftingSheet?
    private var scale: CGFloat = 2
    private var paperLayers: [CALayer] = []
    private var tiles: [TileCoord: GraphiteTile] = [:]
    private var activeTouch: UITouch?
    private var pending = PendingSampleQueue<NSNumber>()
    private var lastPredicted: [StrokeSample] = []
    private var lastPencilActivity: CFTimeInterval = 0
    private var memoryWarningObserver: NSObjectProtocol?

    /// Simulator touches come from the mouse, so let them stand in for the pencil there.
    private static let mouseDraws: Bool = {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true // a resting palm must not block the pencil
        backgroundColor = UIColor(red: 0.965, green: 0.955, blue: 0.925, alpha: 1)
        isOpaque = true
        accessibilityLabel = "제도 용지"
        // Graphite tiles live in their own layer, between the paper and the tools.
        inkLayer.actions = Self.noAnimations
        gridLayer.actions = Self.noAnimations
        gridLayer.isHidden = true
        layer.addSublayer(gridLayer)
        layer.addSublayer(inkLayer)
        addSubview(compassView)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trimHistoryForMemoryWarning() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    isolated deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    // MARK: Setup

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard sheet == nil, let screen = window?.windowScene?.screen else { return }
        scale = screen.scale
        // A square sheet a few screens across; the screen looks at part of it
        // and the overview map moves the view. The desk turns it back when the
        // interface turns.
        let longSide = Double(max(screen.nativeBounds.width, screen.nativeBounds.height))
        let side = Int((longSide * Self.sheetScreens).rounded(.up))
        let ppmm = DisplayDensity.pixelsPerMillimeter(nativeLongSidePixels: longSide)
        let sheet = DraftingSheet(width: side, height: side, pixelsPerMillimeter: ppmm)
        self.sheet = sheet
        presses = LongPress(slop: Self.pressSlopMM * ppmm)
        layPaper(for: sheet)
        superview?.setNeedsLayout()
        notifyHistory()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        compassView.frame = bounds
    }

    /// Side of the square sheet in points, once it exists.
    var sideInPoints: CGFloat? {
        sheet.map { CGFloat($0.width) / scale }
    }

    private func layPaper(for sheet: DraftingSheet) {
        paperLayers.forEach { $0.removeFromSuperlayer() }
        paperLayers.removeAll()
        let texture = sheet.paper
        let image = Self.makeImage(pixels: GraphiteShading.paperPixels(texture), width: texture.size, height: texture.size)
        let step = CGFloat(texture.size) / scale
        let count = (sheet.width + texture.size - 1) / texture.size
        for row in 0..<count {
            for column in 0..<count {
                let layer = CALayer()
                layer.contents = image
                layer.contentsScale = scale
                layer.magnificationFilter = .nearest
                layer.isOpaque = true
                layer.frame = CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: step, height: step)
                layer.actions = Self.noAnimations
                self.layer.insertSublayer(layer, at: 0)
                paperLayers.append(layer)
            }
        }
    }

    // MARK: Graph paper

    /// Prints graph-paper rulings on the sheet (1 mm, 5 mm and 10 mm), or plain paper.
    func setGraphPaper(_ on: Bool) {
        guard let sheet else { return }
        if on, gridLayer.sublayers == nil { ruleGrid(sheet) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gridLayer.isHidden = !on
        CATransaction.commit()
    }

    private func ruleGrid(_ sheet: DraftingSheet) {
        let side = CGFloat(sheet.width) / scale
        let mm = CGFloat(sheet.pixelsPerMillimeter) / scale
        gridLayer.frame = CGRect(x: 0, y: 0, width: side, height: side)
        let colour = UIColor(red: 0.42, green: 0.52, blue: 0.40, alpha: 1)
        for (every, alpha, width) in [(1, 0.16, 0.3), (5, 0.28, 0.45), (10, 0.42, 0.65)] as [(Int, CGFloat, CGFloat)] {
            let path = CGMutablePath()
            let count = Int(side / mm)
            for k in 0...count where k % every == 0 && (every == 10 || k % (every * (every == 1 ? 5 : 2)) != 0) {
                let at = CGFloat(k) * mm
                path.move(to: CGPoint(x: at, y: 0))
                path.addLine(to: CGPoint(x: at, y: side))
                path.move(to: CGPoint(x: 0, y: at))
                path.addLine(to: CGPoint(x: side, y: at))
            }
            let lines = CAShapeLayer()
            lines.frame = gridLayer.bounds
            lines.path = path
            lines.strokeColor = colour.withAlphaComponent(alpha).cgColor
            lines.lineWidth = width
            lines.fillColor = nil
            lines.actions = Self.noAnimations
            gridLayer.addSublayer(lines)
        }
    }

    // MARK: Undo

    func undo() {
        guard sheet?.undo() == true else { return }
        refresh()
        notifyHistory()
    }

    func redo() {
        guard sheet?.redo() == true else { return }
        refresh()
        notifyHistory()
    }

    private func notifyHistory() {
        onHistoryChange?(sheet?.canUndo ?? false, sheet?.canRedo ?? false)
        onOverviewChange?()
    }

    /// How many screens across the square sheet is.
    static let sheetScreens = 2.6

    /// A small picture of the drawing, `size` pixels square, in the sheet's own orientation.
    func overviewImage(size: Int) -> CGImage? {
        guard let sheet else { return nil }
        let densities = sheet.overview(size: size)
        let paper = (r: 0.965, g: 0.955, b: 0.925), lead = (r: 0.05, g: 0.05, b: 0.06)
        let pixels = densities.map { d -> UInt32 in
            let t = Double(min(d * 1.4, 1)) // thin lines vanish when shrunk, so darken a little
            let r = UInt32((paper.r + (lead.r - paper.r) * t) * 255), g = UInt32((paper.g + (lead.g - paper.g) * t) * 255)
            let b = UInt32((paper.b + (lead.b - paper.b) * t) * 255)
            return 0xFF00_0000 | (r << 16) | (g << 8) | b
        }
        return Self.makeImage(pixels: pixels, width: size, height: size)
    }

    /// The tools' outlines as fractions of the sheet, for the overview map.
    var toolOutlines: [[CGPoint]] {
        guard let sheet else { return [] }
        let side = Double(sheet.width)
        return toolShapes.map { shape in
            shape.outline.map { q in
                let p = shape.world(q)
                return CGPoint(x: Double(p.x) / side, y: Double(p.y) / side)
            }
        }
    }

    private func trimHistoryForMemoryWarning() {
        sheet?.trimHistory(toBytes: DraftingSheet.defaultHistoryBudget / 4)
        notifyHistory()
    }

    // MARK: Tools

    /// Puts a tool on the paper, lying level with the screen as it is now, or takes it away.
    func setTool(_ kind: ToolKind, onDesk: Bool) {
        guard let sheet else { return }
        guard onDesk else {
            tools.removeAll { $0.kind == kind }
            holders[kind] = nil
            toolViews[kind]?.isHidden = true
            toolsChanged()
            return
        }
        guard !tools.contains(where: { $0.kind == kind }), let window else { return }
        let spot = Self.restingSpot(kind)
        let onScreen = CGPoint(x: window.bounds.width * spot.x, y: window.bounds.height * spot.y)
        let here = convert(onScreen, from: window)
        let right = convert(CGPoint(x: onScreen.x + 100, y: onScreen.y), from: window)
        let pose = ToolPose(center: CGPoint(x: here.x * scale, y: here.y * scale),
                            angle: atan2(Double(right.y - here.y), Double(right.x - here.x)))
        tools.append(DeskTool(kind: kind, pose: pose))
        showTool(tools[tools.count - 1], sheet: sheet)
        raise(kind)
    }

    /// Where on the screen each tool is first laid, as fractions of its size.
    private static func restingSpot(_ kind: ToolKind) -> CGPoint {
        switch kind {
        case .ruler: CGPoint(x: 0.5, y: 0.5)
        case .setSquare45: CGPoint(x: 0.3, y: 0.38)
        case .setSquare60: CGPoint(x: 0.66, y: 0.38)
        case .circleTemplate: CGPoint(x: 0.5, y: 0.7)
        case .ellipseTemplate: CGPoint(x: 0.5, y: 0.3)
        case .squareTemplate: CGPoint(x: 0.42, y: 0.5)
        case .hexTemplate: CGPoint(x: 0.58, y: 0.6)
        case .arcTemplate: CGPoint(x: 0.5, y: 0.5)
        case .frenchCurveA: CGPoint(x: 0.28, y: 0.48)
        case .frenchCurveB: CGPoint(x: 0.52, y: 0.5)
        case .frenchCurveC: CGPoint(x: 0.76, y: 0.42)
        case .hipCurve: CGPoint(x: 0.5, y: 0.5)
        case .protractor: CGPoint(x: 0.62, y: 0.62)
        }
    }

    private func toolView(_ kind: ToolKind) -> any ToolDisplay {
        if let view = toolViews[kind] { return view }
        let view: any ToolDisplay = switch kind {
        case .ruler: RulerView()
        case .setSquare45, .setSquare60: SetSquareView(kind: kind)
        case .circleTemplate: CircleTemplateView()
        case .ellipseTemplate, .squareTemplate, .hexTemplate, .arcTemplate: ShapeTemplateView(kind: kind)
        case .frenchCurveA, .frenchCurveB, .frenchCurveC: FrenchCurveView(kind: kind)
        case .hipCurve: HipCurveView()
        case .protractor: ProtractorView()
        }
        insertSubview(view, belowSubview: compassView)
        toolViews[kind] = view
        return view
    }

    private func showTool(_ tool: DeskTool, sheet: DraftingSheet) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        toolView(tool.kind).show(tool, scale: scale, pixelsPerMillimeter: sheet.pixelsPerMillimeter)
        CATransaction.commit()
    }

    private func toolsChanged() {
        guard let sheet else { return }
        toolShapes = tools.map { $0.shape(pixelsPerMillimeter: sheet.pixelsPerMillimeter) }
        onOverviewChange?()
    }

    /// Lays a tool on top of the others. Not while a line is being drawn,
    /// since the pencil's guide counts the tools by their order.
    private func raise(_ kind: ToolKind) {
        if activeTouch == nil, let i = tools.firstIndex(where: { $0.kind == kind }) {
            tools.append(tools.remove(at: i))
            if let view = toolViews[kind] { insertSubview(view, belowSubview: compassView) }
        }
        toolsChanged()
    }

    /// A fingertip landing on (or just beside) a tool takes hold of the topmost one there.
    private func grabTool(_ touch: UITouch) -> Bool {
        guard let sheet, touch.majorRadius < Self.fingertipRadius else { return false }
        let point = pixelLocation(touch)
        let margin = Self.gripMarginMM * sheet.pixelsPerMillimeter
        guard let i = tools.indices.last(where: {
            toolShapes[$0].outlineContains(point, margin: margin) && holders[tools[$0].kind, default: []].count < 2
        }) else { return false }
        let kind = tools[i].kind
        if holders[kind, default: []].isEmpty { stacked[kind] = overlapping(kind) }
        holders[kind, default: []].append((touch, point))
        raise(kind)
        return true
    }

    private func moveTools(_ touches: Set<UITouch>) {
        guard let sheet else { return }
        var moved = false
        for (kind, held) in holders where held.contains(where: { touches.contains($0.touch) }) {
            guard let i = tools.firstIndex(where: { $0.kind == kind }) else { continue }
            let now = held.map { pixelLocation($0.touch) }
            var pose = tools[i].pose
            switch held.count {
            case 1: pose = RigidMotion.slide(pose, from: held[0].point, to: now[0])
            default: pose = RigidMotion.slideAndTurn(pose, from: (held[0].point, held[1].point), to: (now[0], now[1]))
            }
            // Butt against the other tools instead of passing through them.
            if ToolContact.collides(kind) {
                let moving = ToolContact.polygon(DeskTool(kind: kind, pose: pose).shape(pixelsPerMillimeter: sheet.pixelsPerMillimeter))
                let free = stacked[kind] ?? []
                let obstacles = tools.indices
                    .filter { tools[$0].kind != kind && ToolContact.collides(tools[$0].kind) && !free.contains(tools[$0].kind) }
                    .map { ToolContact.polygon(toolShapes[$0]) }
                let push = ToolContact.resolve(moving, against: obstacles)
                pose.center.x += push.dx
                pose.center.y += push.dy
            }
            tools[i].pose = pose
            holders[kind] = zip(held, now).map { ($0.touch, $1) }
            showTool(tools[i], sheet: sheet)
            moved = true
        }
        if moved { toolsChanged() }
    }

    /// The rigid tools overlapping `kind` where it lies now.
    private func overlapping(_ kind: ToolKind) -> Set<ToolKind> {
        guard ToolContact.collides(kind), let i = tools.firstIndex(where: { $0.kind == kind }) else { return [] }
        let mine = ToolContact.polygon(toolShapes[i])
        return Set(tools.indices.filter { $0 != i && ToolContact.collides(tools[$0].kind)
            && ToolContact.overlaps(mine, ToolContact.polygon(toolShapes[$0])) }.map { tools[$0].kind })
    }

    private func releaseTools(_ touches: Set<UITouch>) {
        for kind in holders.keys { holders[kind]?.removeAll { touches.contains($0.touch) } }
    }

    /// How far outside a tool a fingertip still catches it.
    private static let gripMarginMM = 4.0

    // MARK: Compass

    /// Takes the compass out, so a finger held still plants its needle, or puts it away.
    /// Nothing shows until the needle goes in.
    func setCompass(onDesk: Bool) {
        compassOnDesk = onDesk
        if !onDesk { pullNeedle() }
    }

    private func plantNeedle(at point: CGPoint, finger: UITouch) {
        guard compassOnDesk, activeTouch == nil else { return }
        var compass = Compass(needle: point)
        if compassStyle.spread == .kept, let keptSpread {
            compass.spread = keptSpread.spread
            compass.leadAngle = keptSpread.angle
        }
        self.compass = compass
        needleIn = true
        needleFinger = (finger, point)
        needleSettled = false
        pullNeedleAfterStroke = false
        showCompass()
    }

    /// Takes the needle out of the paper, and the compass with it, or does so
    /// as soon as the compass stops drawing.
    private func pullNeedle() {
        needleFinger = nil
        if activeTouch != nil, guide?.arc != nil {
            pullNeedleAfterStroke = true
            return
        }
        needleIn = false
        compass = nil
        pullNeedleAfterStroke = false
        compassView.hide()
    }

    private func moveNeedle(with finger: UITouch) {
        guard let held = needleFinger, held.touch == finger else { return }
        let now = pixelLocation(finger)
        needleFinger?.point = now
        guard !needleSettled, var compass else { return }
        compass.needle.x += now.x - held.point.x
        compass.needle.y += now.y - held.point.y
        self.compass = compass
        showCompass()
    }

    private func showCompass() {
        guard let compass, let sheet else { return }
        compassView.show(compass, scale: scale, pixelsPerMillimeter: sheet.pixelsPerMillimeter)
    }

    /// Lead and needle follow the compass that just drew, and the legs keep their spread.
    private func finishCompassStroke(drew: Bool) {
        if drew, let arc = guide?.arc, let angle = arc.angle, var compass {
            compass.leadAngle = angle
            self.compass = compass
            keptSpread = (arc.radius, angle)
        }
        guide = nil
        if pullNeedleAfterStroke { pullNeedle() } else { showCompass() }
    }

    private func scheduleLongPressCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + presses.duration + 0.02) { [weak self] in
            self?.checkLongPresses()
        }
    }

    private func checkLongPresses() {
        for (touch, _) in presses.due(at: CACurrentMediaTime()) where touch.phase != .ended && touch.phase != .cancelled {
            if compassOnDesk {
                // While a finger holds the needle in, another one can't move it.
                guard needleFinger == nil else { continue }
                plantNeedle(at: pixelLocation(touch), finger: touch)
            } else if isDeliberateFinger(touch) {
                onFingerTouch?()
            }
        }
    }

    /// A finger may drift this far and still be holding still.
    private static let pressSlopMM = 2.5
    /// A tap this close to the needle pulls it out.
    private static let needleHeadMM = 6.0

    // MARK: Touches

    /// In the simulator the mouse is the pencil, and a two-finger (option-drag) gesture is the hand.
    private func isFinger(_ touch: UITouch, _ event: UIEvent?) -> Bool {
        guard touch.type == .direct else { return false }
        guard Self.mouseDraws else { return true }
        return (event?.allTouches?.filter { $0.type == .direct }.count ?? 0) >= 2
    }

    private func draws(_ touch: UITouch, _ event: UIEvent?) -> Bool {
        touch.type == .pencil || (Self.mouseDraws && touch.type == .direct && !isFinger(touch, event))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = CACurrentMediaTime()
        for touch in touches where isFinger(touch, event) {
            guard touch.majorRadius < Self.fingertipRadius else { continue }
            if grabTool(touch) { continue }
            // A finger held still may plant the needle; once it moves it may rub with the eraser.
            presses.begin(touch, at: pixelLocation(touch), time: now)
            scheduleLongPressCheck()
        }
        guard activeTouch == nil, let touch = touches.first(where: { draws($0, event) }) else { return }
        startStroke(touch, erasing: false, event: event)
    }

    /// Starts a line, or with `erasing` a rub that began at `start`.
    private func startStroke(_ touch: UITouch, erasing: Bool, from start: CGPoint? = nil, event: UIEvent?) {
        guard let sheet else { return }
        activeTouch = touch
        pending = PendingSampleQueue()
        lastPredicted = []
        if erasing {
            var tracker = RubTracker(pixelsPerMillimeter: sheet.pixelsPerMillimeter)
            sheet.beginErasing()
            if let start {
                sheet.extendStroke(with: [tracker.track(StrokeSample(location: start))], predicted: [])
            }
            guide = .rub(tracker)
        } else {
            let grade = currentGrade()
            guide = makeGuide(startingAt: sample(touch).location, grade: grade, sheet: sheet)
            sheet.beginStroke(grade: grade)
        }
        feed(touch, event: event)
    }

    /// The compass if its lead can reach where the pencil landed, otherwise the ruler's edge.
    private func makeGuide(startingAt start: CGPoint, grade: PencilGrade, sheet: DraftingSheet) -> StrokeGuide {
        let ppmm = sheet.pixelsPerMillimeter
        if needleIn, var compass, let spread = compass.spread(forPencilAt: start, keepsSpread: compassStyle.spread == .kept,
                                                    pixelsPerMillimeter: ppmm) {
            compass.spread = spread
            self.compass = compass
            needleSettled = true
            return .arc(ArcGuide(center: compass.needle, radius: spread, pixelsPerMillimeter: ppmm))
        }
        return .edge(EdgeGuide(style: .standard, pixelsPerMillimeter: ppmm,
                               contactOffset: grade.parameters.lineWidthMM / 2 * ppmm))
    }

    /// Fingers that end or are taken away: the ruler lets go, the needle may come out.
    private func fingersLifted(_ touches: Set<UITouch>, cancelled: Bool) {
        releaseTools(touches)
        let now = CACurrentMediaTime()
        for touch in touches where touch.type == .direct {
            if let held = needleFinger, held.touch == touch {
                needleFinger = nil
                if compassStyle.needle == .whileHeld { pullNeedle() }
                presses.cancel(touch)
                continue
            }
            let ending = cancelled ? nil : presses.end(touch, time: now)
            if cancelled { presses.cancel(touch) }
            guard ending == .tap else { continue }
            let point = pixelLocation(touch)
            if needleIn, let compass, needleFinger == nil, let sheet,
               compass.needleHeadContains(point, radius: Self.needleHeadMM * sheet.pixelsPerMillimeter) {
                pullNeedle()
            } else if isDeliberateFinger(touch) {
                onFingerTouch?()
            }
        }
    }

    /// A fingertip on the paper while the pencil is idle, not a palm resting as you draw.
    private func isDeliberateFinger(_ touch: UITouch) -> Bool {
        guard !Self.mouseDraws, !eraserInHand, touch.type == .direct, activeTouch == nil else { return false }
        let pencilIdle = CACurrentMediaTime() - lastPencilActivity > Self.palmGrace
        return pencilIdle && touch.majorRadius < Self.fingertipRadius
    }

    /// Palms keep landing for a while after a stroke ends.
    private static let palmGrace: CFTimeInterval = 3
    /// Contact radius, in points, above which a touch is a palm or side of the hand.
    /// A fingertip pressed and held flat reads up to about 40.
    private static let fingertipRadius: CGFloat = 45

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        moveTools(touches)
        for touch in touches where touch.type == .direct && touch != activeTouch {
            if let held = needleFinger, held.touch == touch {
                moveNeedle(with: touch)
            } else if presses.move(touch, to: pixelLocation(touch)) {
                if eraserInHand, activeTouch == nil {
                    startStroke(touch, erasing: true, from: presses.start(of: touch), event: event)
                    presses.cancel(touch)
                } else if isDeliberateFinger(touch) {
                    onFingerTouch?() // rubbing the paper as if to draw
                }
            }
        }
        guard let touch = activeTouch, touches.contains(touch) else { return }
        feed(touch, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let pencil = activeTouch
        if let touch = activeTouch, touches.contains(touch), let sheet {
            feed(touch, event: event, predicting: false)
            // Whatever is still estimated goes in as it is; the pencil has lifted.
            extend(with: pending.flush())
            sheet.endStroke()
            activeTouch = nil
            finishCompassStroke(drew: true)
            refresh()
            notifyHistory()
        }
        fingersLifted(touches.filter { $0 != pencil }, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let pencil = activeTouch
        if let touch = activeTouch, touches.contains(touch), let sheet {
            sheet.cancelStroke()
            _ = pending.flush()
            lastPredicted = []
            activeTouch = nil
            finishCompassStroke(drew: false)
            refresh()
            notifyHistory()
        }
        fingersLifted(touches.filter { $0 != pencil }, cancelled: true)
    }

    /// Apple Pencil first reports force as an estimate and sends the measured
    /// value a moment later. Held-back samples are drawn as provisional until then.
    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        guard activeTouch != nil else { return }
        var released: [StrokeSample] = []
        for touch in touches {
            guard let index = touch.estimationUpdateIndex else { continue }
            let measured = sample(touch)
            released += pending.update(key: index, stillAwaiting: Self.awaitsForce(touch)) {
                $0.pressure = measured.pressure
                $0.altitude = measured.altitude
                $0.azimuth = measured.azimuth
            }
        }
        guard !released.isEmpty else { return }
        extend(with: released)
    }

    private func feed(_ touch: UITouch, event: UIEvent?, predicting: Bool = true) {
        lastPencilActivity = CACurrentMediaTime()
        var released: [StrokeSample] = []
        for coalesced in event?.coalescedTouches(for: touch) ?? [touch] {
            let key = Self.awaitsForce(coalesced) ? coalesced.estimationUpdateIndex : nil
            released += pending.append(sample(coalesced), awaitingUpdate: key)
        }
        lastPredicted = predicting ? (event?.predictedTouches(for: touch) ?? []).map(sample) : []
        extend(with: released)
    }

    /// Runs samples whose pressure is now known through the guide (ruler edge
    /// or compass) into the stroke. Samples still waiting and predicted ones
    /// go through a copy of the guide, so they never change the real one.
    private func extend(with released: [StrokeSample]) {
        guard let sheet else { return }
        var final = released
        var ahead = pending.provisional + lastPredicted
        if var guide {
            final = guide.guide(released, tools: toolShapes)
            self.guide = guide
            var lookahead = guide
            ahead = lookahead.guide(ahead, tools: toolShapes)
            if let angle = lookahead.arc?.angle, var compass {
                compass.leadAngle = angle
                self.compass = compass
                showCompass()
            }
        }
        sheet.extendStroke(with: final, predicted: ahead)
        refresh()
    }

    private func pixelLocation(_ touch: UITouch) -> CGPoint {
        let p = touch.preciseLocation(in: self)
        return CGPoint(x: p.x * scale, y: p.y * scale)
    }

    private static func awaitsForce(_ touch: UITouch) -> Bool {
        touch.type == .pencil && touch.estimatedPropertiesExpectingUpdates.contains(.force)
    }

    private func sample(_ touch: UITouch) -> StrokeSample {
        let point = touch.preciseLocation(in: self)
        let isPencil = touch.type == .pencil
        return StrokeSample(
            location: CGPoint(x: point.x * scale, y: point.y * scale),
            pressure: isPencil
                ? PressureCurve.pressure(force: Double(touch.force), maximumPossibleForce: Double(touch.maximumPossibleForce))
                : 0.5,
            altitude: isPencil ? Double(touch.altitudeAngle) : .pi / 2,
            azimuth: isPencil ? Double(touch.azimuthAngle(in: self)) : 0
        )
    }

    // MARK: Drawing graphite

    private func refresh() {
        guard let sheet else { return }
        let regions = sheet.takeDirtyRegions()
        guard !regions.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (coord, rect) in regions {
            let tile = tiles[coord] ?? makeTile(coord)
            tile.pixels.withUnsafeMutableBufferPointer { sheet.renderGraphite(tile: coord, rect: rect, into: $0) }
            tile.layer.contents = Self.makeImage(pixels: tile.pixels, width: GraphiteRaster.tileSize, height: GraphiteRaster.tileSize)
        }
        CATransaction.commit()
    }

    private func makeTile(_ coord: TileCoord) -> GraphiteTile {
        let side = CGFloat(GraphiteRaster.tileSize) / scale
        let layer = CALayer()
        layer.frame = CGRect(x: CGFloat(coord.x) * side, y: CGFloat(coord.y) * side, width: side, height: side)
        layer.contentsScale = scale
        layer.magnificationFilter = .nearest
        layer.actions = Self.noAnimations
        inkLayer.addSublayer(layer)
        let tile = GraphiteTile(layer: layer)
        tiles[coord] = tile
        return tile
    }

    private static let noAnimations: [String: CAAction] = [
        "contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull(),
    ]

    /// Copies the pixels into a new image, so later writes never show through.
    static func makeImage(pixels: [UInt32], width: Int, height: Int) -> CGImage? {
        let data = pixels.withUnsafeBytes { Data($0) } as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

/// One tile of graphite on screen and the pixels behind it.
private final class GraphiteTile {
    let layer: CALayer
    var pixels = [UInt32](repeating: 0, count: GraphiteRaster.tileArea)
    init(layer: CALayer) { self.layer = layer }
}
