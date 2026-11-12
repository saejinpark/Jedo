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
    /// Called when sheets come, go, change order or are hidden: the sheets bottom first, and which are hidden.
    var onLayersChange: ((_ layers: [PaperLayer], _ hidden: Set<Int>) -> Void)?
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
    /// Which eraser is in hand.
    var eraserKind: EraserKind = .rubber
    /// Whether the hand holds the knife: the pencil cuts tone instead of
    /// drawing, and a finger tapping a cut-off piece of tone peels it away.
    var knifeInHand = false

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
    /// Holds the paper's own graphite and what the carbon copied onto it.
    private let inkLayer = CALayer()

    /// The drawing paper.
    private(set) var sheet: DraftingSheet?
    private var paperSurface: GraphiteSurface?
    /// What the carbon has copied onto the paper, kept apart so it can be its own colour.
    private var copySurface: GraphiteSurface?
    private var scale: CGFloat = 2
    private var paperLayers: [CALayer] = []

    /// Soft sheets on the paper, bottom first: grid sheets and the carbon, in any order.
    private(set) var layers: [PaperLayer] = []
    private var layerViews: [Int: PaperLayerView] = [:]
    /// Each grid sheet's own drawing, which moves with it.
    private var layerSurfaces: [Int: GraphiteSurface] = [:]
    /// What carbon lying over a grid sheet has copied onto it.
    private var layerCopies: [Int: GraphiteSurface] = [:]
    /// Fingers holding each sheet by its edge.
    private var layerHolders: [Int: [(touch: UITouch, point: CGPoint)]] = [:]
    /// Sheets set aside for now: not seen, not drawn on, not picked up.
    private var hiddenLayers: Set<Int> = []
    private var nextLayerID = 1
    /// Under the tools, above the paper.
    private let sheetsView = UIView()
    /// Surfaces the stroke in progress is marking.
    private var marking: [SurfaceID] = []
    private var markingErases = false
    /// Each pencil's point, worn as it draws.
    private var leads: [PencilGrade: LeadPoint] = [:]
    /// The grade of the stroke in progress and where its line last was, for wear.
    private var markingGrade: PencilGrade = .hb
    private var lastWorn: CGPoint?
    /// The barrel's turn in the hand, when the pencil reports it (Apple Pencil Pro).
    private var roll: Double?
    /// Called when a pencil's point wears, turns or is sharpened, with its worst side (0...1).
    var onLeadChange: ((PencilGrade, Double) -> Void)?
    /// The stroke in progress, pencil and line, for the stroke log.
    private var recorder: StrokeRecorder?
    /// The pencil's own samples for what `lay` is about to draw, for the log.
    private var pendingRaw: [StrokeSample]?
    private var recordStarted: (date: Date, time: CFTimeInterval) = (.now, 0)
    /// Strokes, rubs, cuts and peels, newest last.
    private var undoStack: [UndoStep] = []
    private var redoStack: [UndoStep] = []

    private enum UndoStep {
        /// A stroke or rub, by the surfaces it changed.
        case marks([SurfaceID])
        /// A cut or peel, with each sheet of tone before and after.
        case tones([Int: (before: ToneCut, after: ToneCut)])

        func without(_ id: Int) -> UndoStep? {
            switch self {
            case .marks(let ids):
                let left = ids.filter { $0 != .sheet(id) && $0 != .sheetCopy(id) }
                return left.isEmpty ? nil : .marks(left)
            case .tones(let changes):
                let left = changes.filter { $0.key != id }
                return left.isEmpty ? nil : .tones(left)
            }
        }
    }

    /// Pins pushed in at vanishing points, in paper pixels.
    private(set) var pins: [CGPoint] = []
    private let pinsView = PinsView()
    /// A finger moving a pin, by the pin's index.
    private var pinHolder: (touch: UITouch, pin: Int)?
    /// Tools resting against a pin while one finger moves them: the pin and the side touching it.
    private var pivots: [ToolKind: (pin: Int, side: Int)] = [:]
    /// Called when pins come or go.
    var onPinsChange: ((Int) -> Void)?

    /// What the knife has left of each sheet of tone.
    private var toneCuts: [Int: ToneCut] = [:]
    /// While the knife cuts: each sheet of tone as it was before.
    private var cutting: [Int: ToneCut]?
    private var lastCut: CGPoint?
    private var cutStart: CGPoint?
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
        backgroundColor = Self.deskColour
        isOpaque = true
        accessibilityLabel = "제도 용지"
        // Graphite tiles live in their own layer, between the paper and the tools.
        inkLayer.actions = Self.noAnimations
        layer.addSublayer(inkLayer)
        sheetsView.isUserInteractionEnabled = false
        addSubview(sheetsView)
        addSubview(pinsView)
        addSubview(compassView)
        let pencil = UIPencilInteraction(delegate: self)
        addInteraction(pencil)
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

    /// Lays the drawing paper on the desk. Once only: it stays put, the background of everything.
    func start(on paper: PaperSize) {
        guard paperSize == nil else { return }
        paperSize = paper
        setUp()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setUp()
    }

    private func setUp() {
        guard sheet == nil, var paper = paperSize, let screen = window?.windowScene?.screen else { return }
        scale = screen.scale
        // A square desk with the paper fixed in its middle; the screen looks
        // at part of it and the overview map moves the view. The desk turns
        // it back when the interface turns.
        let longSide = Double(max(screen.nativeBounds.width, screen.nativeBounds.height))
        let ppmm = DisplayDensity.pixelsPerMillimeter(nativeLongSidePixels: longSide)
        if paper.fitsScreen, let window {
            // The screen as it is held now, to the pixel.
            paper.screenWidthMM = (Double(window.bounds.width * scale) / ppmm)
            paper.screenHeightMM = (Double(window.bounds.height * scale) / ppmm)
            paperSize = paper
        }
        let side = Int((paper.deskSideMM(minimumMM: longSide / ppmm) * ppmm).rounded(.up))
        let (w, h) = (paper.sizeMM.width * ppmm, paper.sizeMM.height * ppmm)
        paperRect = CGRect(x: ((Double(side) - w) / 2).rounded(), y: ((Double(side) - h) / 2).rounded(), width: w.rounded(), height: h.rounded())
        let sheet = DraftingSheet(width: side, height: side, pixelsPerMillimeter: ppmm)
        self.sheet = sheet
        let paperSurface = GraphiteSurface(sheet: sheet, scale: scale)
        let copySurface = GraphiteSurface(sheet: DraftingSheet(width: side, height: side, pixelsPerMillimeter: ppmm),
                                          scale: scale, shading: GraphiteShading.carbonLookup)
        inkLayer.addSublayer(paperSurface.layer)
        inkLayer.addSublayer(copySurface.layer)
        self.paperSurface = paperSurface
        self.copySurface = copySurface
        presses = LongPress(slop: Self.pressSlopMM * ppmm)
        layPaper(for: sheet)
        superview?.setNeedsLayout()
        notifyHistory()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        compassView.frame = bounds
        pinsView.frame = bounds
        sheetsView.frame = bounds
    }

    /// The paper on the desk, in pixels.
    private(set) var paperRect = CGRect.zero
    private var paperSize: PaperSize?

    private var paperOutline: [CGPoint] {
        [CGPoint(x: paperRect.minX, y: paperRect.minY), CGPoint(x: paperRect.maxX, y: paperRect.minY),
         CGPoint(x: paperRect.maxX, y: paperRect.maxY), CGPoint(x: paperRect.minX, y: paperRect.maxY)]
    }

    /// Paper millimetres, from its top-left corner, at a point of this view.
    func paperMillimetres(at point: CGPoint) -> CGPoint? {
        guard let sheet else { return nil }
        let ppmm = sheet.pixelsPerMillimeter
        return CGPoint(x: (Double(point.x * scale) - Double(paperRect.minX)) / ppmm,
                       y: (Double(point.y * scale) - Double(paperRect.minY)) / ppmm)
    }

    /// The paper's size in points (untouched by the canvas's turn), once it is laid.
    var paperSizeInPoints: CGSize? {
        sheet == nil ? nil : CGSize(width: paperRect.width / scale, height: paperRect.height / scale)
    }

    /// Whether the paper is exactly the screen, so the view never moves.
    var paperFitsScreen: Bool { sheet != nil && paperSize?.fitsScreen == true }

    /// The paper's width and height in millimetres, once it is laid.
    var paperSizeMM: (width: Double, height: Double)? { sheet == nil ? nil : paperSize?.sizeMM }

    /// The paper as it looks, without the tools in the hand: the paper alone,
    /// or with the grid sheets and carbon lying on it. Its long side is kept
    /// under `exportMaxPixels`.
    func exportImage(includeSheets: Bool) -> UIImage? {
        guard sheet != nil, activeTouch == nil, paperRect.width > 0 else { return nil }
        let frame = CGRect(x: paperRect.minX / scale, y: paperRect.minY / scale,
                           width: paperRect.width / scale, height: paperRect.height / scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(scale, Self.exportMaxPixels / max(frame.width, frame.height))
        format.opaque = true
        let toolsShown = toolViews.filter { !$0.value.isHidden }.map(\.key)
        let compassShown = !compassView.isHidden
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for kind in toolsShown { toolViews[kind]?.isHidden = true }
        compassView.isHidden = true
        sheetsView.isHidden = !includeSheets
        defer {
            for kind in toolsShown { toolViews[kind]?.isHidden = false }
            compassView.isHidden = !compassShown
            sheetsView.isHidden = false
            CATransaction.commit()
        }
        return UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
            context.cgContext.translateBy(x: -frame.minX, y: -frame.minY)
            layer.render(in: context.cgContext)
        }
    }

    static let exportMaxPixels: CGFloat = 6000

    /// The desk the paper lies on.
    static let deskColour = UIColor(red: 0.74, green: 0.72, blue: 0.68, alpha: 1)

    /// Side of the square desk in points, once it exists.
    var sideInPoints: CGFloat? {
        sheet.map { CGFloat($0.width) / scale }
    }

    private func layPaper(for sheet: DraftingSheet) {
        paperLayers.forEach { $0.removeFromSuperlayer() }
        paperLayers.removeAll()
        let texture = sheet.paper
        let image = Self.makeImage(pixels: GraphiteShading.paperPixels(texture), width: texture.size, height: texture.size)
        let step = CGFloat(texture.size) / scale
        let frame = CGRect(x: paperRect.minX / scale, y: paperRect.minY / scale, width: paperRect.width / scale, height: paperRect.height / scale)
        // The paper's edge: clipped texture over a soft shadow on the desk.
        let shadow = CALayer()
        shadow.frame = frame
        shadow.backgroundColor = UIColor(white: 0.5, alpha: 1).cgColor
        shadow.shadowColor = UIColor.black.cgColor
        shadow.shadowOpacity = 0.22
        shadow.shadowRadius = 4
        shadow.shadowOffset = CGSize(width: 0, height: 1.5)
        shadow.shadowPath = CGPath(rect: CGRect(origin: .zero, size: frame.size), transform: nil)
        let paper = CALayer()
        paper.frame = frame
        paper.masksToBounds = true
        // Tiles keep to the desk's grid so the grain lines up with the graphite's.
        let first = (x: Int(frame.minX / step), y: Int(frame.minY / step))
        let last = (x: Int(frame.maxX / step), y: Int(frame.maxY / step))
        for row in first.y...last.y {
            for column in first.x...last.x {
                let layer = CALayer()
                layer.contents = image
                layer.contentsScale = scale
                layer.magnificationFilter = .nearest
                layer.isOpaque = true
                layer.frame = CGRect(x: CGFloat(column) * step - frame.minX, y: CGFloat(row) * step - frame.minY, width: step, height: step)
                layer.actions = Self.noAnimations
                paper.addSublayer(layer)
            }
        }
        for layer in [paper, shadow] {
            layer.actions = Self.noAnimations
            self.layer.insertSublayer(layer, at: 0)
            paperLayers.append(layer)
        }
    }

    // MARK: Undo

    func undo() {
        guard activeTouch == nil, let step = undoStack.popLast() else { return }
        switch step {
        case .marks(let ids): for id in ids { _ = surface(id)?.sheet.undo() }
        case .tones(let changes): for (id, change) in changes { setTone(id, change.before) }
        }
        redoStack.append(step)
        refresh()
        notifyHistory()
    }

    func redo() {
        guard activeTouch == nil, let step = redoStack.popLast() else { return }
        switch step {
        case .marks(let ids): for id in ids { _ = surface(id)?.sheet.redo() }
        case .tones(let changes): for (id, change) in changes { setTone(id, change.after) }
        }
        undoStack.append(step)
        refresh()
        notifyHistory()
    }

    private func notifyHistory() {
        onHistoryChange?(!undoStack.isEmpty && activeTouch == nil, !redoStack.isEmpty && activeTouch == nil)
        onOverviewChange?()
    }


    /// A small picture of the drawing, `size` pixels square, in the sheet's own orientation.
    func overviewImage(size: Int) -> CGImage? {
        guard let sheet else { return nil }
        var densities = sheet.overview(size: size)
        if let copied = copySurface?.sheet.overview(size: size) {
            for i in densities.indices where copied[i] > densities[i] { densities[i] = copied[i] }
        }
        let lead = (r: 0.05, g: 0.05, b: 0.06)
        var desk: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0, 0, 0, 0)
        Self.deskColour.getRed(&desk.r, green: &desk.g, blue: &desk.b, alpha: &desk.a)
        let cell = Double(sheet.width) / Double(size)
        let pixels = densities.enumerated().map { i, d -> UInt32 in
            let centre = CGPoint(x: (Double(i % size) + 0.5) * cell, y: (Double(i / size) + 0.5) * cell)
            let paper = paperRect.contains(centre) ? (r: 0.965, g: 0.955, b: 0.925) : (r: Double(desk.r), g: Double(desk.g), b: Double(desk.b))
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
        let sheets = layers.filter { !hiddenLayers.contains($0.id) }.map { layer in
            layer.outline(pixelsPerMillimeter: sheet.pixelsPerMillimeter).map { CGPoint(x: Double($0.x) / side, y: Double($0.y) / side) }
        }
        let r = 2 * sheet.pixelsPerMillimeter
        let pinMarks = pins.map { p in
            [CGPoint(x: p.x - r, y: p.y - r), CGPoint(x: p.x + r, y: p.y - r), CGPoint(x: p.x + r, y: p.y + r), CGPoint(x: p.x - r, y: p.y + r)]
                .map { CGPoint(x: Double($0.x) / side, y: Double($0.y) / side) }
        }
        return sheets + pinMarks + toolShapes.map { shape in
            shape.outline.map { q in
                let p = shape.world(q)
                return CGPoint(x: Double(p.x) / side, y: Double(p.y) / side)
            }
        }
    }

    private func trimHistoryForMemoryWarning() {
        for surface in allSurfaces { surface.sheet.trimHistory(toBytes: DraftingSheet.defaultHistoryBudget / 8) }
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
        guard !tools.contains(where: { $0.kind == kind }), var pose = screenPose(at: Self.restingSpot(kind)) else { return }
        if kind == .parallelRule { pose = ParallelRule.constrain(pose, boardCentreX: Double(paperRect.midX)) }
        tools.append(DeskTool(kind: kind, pose: pose))
        showTool(tools[tools.count - 1], sheet: sheet)
        raise(kind)
    }

    /// A spot on the screen (as fractions of its size) on the paper, lying level with the screen.
    private func screenPose(at spot: CGPoint) -> ToolPose? {
        guard let window else { return nil }
        let onScreen = CGPoint(x: window.bounds.width * spot.x, y: window.bounds.height * spot.y)
        let here = convert(onScreen, from: window)
        let right = convert(CGPoint(x: onScreen.x + 100, y: onScreen.y), from: window)
        return ToolPose(center: CGPoint(x: here.x * scale, y: here.y * scale),
                        angle: atan2(Double(right.y - here.y), Double(right.x - here.x)))
    }

    /// Where on the screen each tool is first laid, as fractions of its size.
    private static func restingSpot(_ kind: ToolKind) -> CGPoint {
        switch kind {
        case .ruler: CGPoint(x: 0.5, y: 0.5)
        case .parallelRule: CGPoint(x: 0.5, y: 0.62)
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
        case .parallelRule: ParallelRuleView(kind: kind)
        case .setSquare45, .setSquare60: SetSquareView(kind: kind)
        case .circleTemplate: CircleTemplateView()
        case .ellipseTemplate, .squareTemplate, .hexTemplate, .arcTemplate: ShapeTemplateView(kind: kind)
        case .frenchCurveA, .frenchCurveB, .frenchCurveC: FrenchCurveView(kind: kind)
        case .hipCurve: HipCurveView()
        case .protractor: ProtractorView()
        }
        insertSubview(view, belowSubview: pinsView)
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
            if let view = toolViews[kind] { insertSubview(view, belowSubview: pinsView) }
        }
        toolsChanged()
    }

    /// A fingertip landing on (or just beside) a tool takes hold of the topmost one there.
    private func grabTool(_ touch: UITouch) -> Bool {
        guard let sheet, touch.majorRadius < Self.fingertipRadius else { return false }
        let point = pixelLocation(touch)
        // A pin's head sits above everything: a fingertip on it moves the pin.
        if pinHolder == nil, let i = pins.indices.min(by: { pins[$0].distance(to: point) < pins[$1].distance(to: point) }),
           pins[i].distance(to: point) <= PinsView.headMM * 1.4 * sheet.pixelsPerMillimeter {
            pinHolder = (touch, i)
            return true
        }
        let margin = Self.gripMarginMM * sheet.pixelsPerMillimeter
        guard let i = tools.indices.last(where: {
            toolShapes[$0].outlineContains(point, margin: margin) && holders[tools[$0].kind, default: []].count < 2
        }) else { return grabLayer(touch, at: point) }
        let kind = tools[i].kind
        if holders[kind, default: []].isEmpty {
            stacked[kind] = overlapping(kind)
            // Already resting on a pin: one finger swings it about the pin from the start.
            if ToolContact.collides(kind), kind != .parallelRule,
               let p = pins.indices.first(where: { PinPivot.contact(toolShapes[i], pin: pins[$0], pixelsPerMillimeter: sheet.pixelsPerMillimeter) != nil }),
               let side = PinPivot.contact(toolShapes[i], pin: pins[p], pixelsPerMillimeter: sheet.pixelsPerMillimeter) {
                pivots[kind] = (p, side)
            }
        } else {
            // A second finger lifts it off the pin to move it freely.
            pivots[kind] = nil
        }
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
            let ppmm = sheet.pixelsPerMillimeter
            let shapeAt = { (p: ToolPose) in DeskTool(kind: kind, pose: p).shape(pixelsPerMillimeter: ppmm) }
            var onPin = false
            if held.count == 1, let rest = pivots[kind], rest.pin < pins.count,
               let swung = PinPivot.pivot(pose, side: rest.side, pin: pins[rest.pin], from: held[0].point, to: now[0],
                                          shapeAt: shapeAt, pixelsPerMillimeter: ppmm) {
                // Resting on a pin: one finger swings it about the pin and slides it along.
                pose = swung
                onPin = true
            } else {
                pivots[kind] = nil
                switch held.count {
                case 1: pose = RigidMotion.slide(pose, from: held[0].point, to: now[0])
                default: pose = RigidMotion.slideAndTurn(pose, from: (held[0].point, held[1].point), to: (now[0], now[1]))
                }
                // The parallel rule only travels up and down the board.
                if kind == .parallelRule {
                    pose = ParallelRule.constrain(pose, boardCentreX: Double(paperRect.midX))
                }
                // Pushed against a pin with one finger, a straight edge comes to rest on it.
                if held.count == 1, ToolContact.collides(kind), kind != .parallelRule {
                    let before = toolShapes[i], after = shapeAt(pose)
                    for (p, pin) in pins.enumerated() {
                        guard let side = PinPivot.contact(after, pin: pin, before: before, pixelsPerMillimeter: ppmm) else { continue }
                        pose = PinPivot.settle(pose, side: side, pin: pin, shapeAt: shapeAt, pixelsPerMillimeter: ppmm)
                        pivots[kind] = (p, side)
                        onPin = true
                        break
                    }
                }
            }
            // Butt against the other tools instead of passing through them.
            if ToolContact.collides(kind), !onPin, kind != .parallelRule {
                let free = stacked[kind] ?? []
                let obstacles = tools.indices
                    .filter { tools[$0].kind != kind && ToolContact.collides(tools[$0].kind) && !free.contains(tools[$0].kind) }
                    .map { ToolContact.polygon(toolShapes[$0]) }
                // Travel until it touches, then slide and turn: never shoved back out from under the fingers.
                pose = ToolContact.advance(from: tools[i].pose, to: pose, outline: { ToolContact.polygon(shapeAt($0)) },
                                           against: obstacles)
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
        // A tool let go stays where it lies; picked up again, it finds the pin anew.
        for kind in pivots.keys where holders[kind, default: []].isEmpty { pivots[kind] = nil }
        if let held = pinHolder, touches.contains(held.touch) { pinHolder = nil }
        for id in layerHolders.keys { layerHolders[id]?.removeAll { touches.contains($0.touch) } }
        layerHolders = layerHolders.filter { !$0.value.isEmpty }
    }

    /// How far outside a tool a fingertip still catches it.
    private static let gripMarginMM = 4.0

    // MARK: Perspective pins

    /// Pushes a pin into the board in the middle of the screen. Drag it to the vanishing point.
    func addPin() {
        guard let pose = screenPose(at: CGPoint(x: 0.5, y: 0.42)), pins.count < Self.maxPins else { return }
        // A second or third pin lands beside the last, not on top of it.
        let step = 30 * (sheet?.pixelsPerMillimeter ?? 10) * Double(pins.count)
        pins.append(CGPoint(x: Double(pose.center.x) + step, y: pose.center.y))
        pinsChanged()
    }

    /// Pulls every pin out.
    func removePins() {
        pins.removeAll()
        pivots.removeAll()
        pinHolder = nil
        pinsChanged()
    }

    private func pinsChanged() {
        pinsView.show(pins.map { CGPoint(x: $0.x / scale, y: $0.y / scale) },
                      headRadius: CGFloat(PinsView.headMM * (sheet?.pixelsPerMillimeter ?? 10)) / scale)
        onPinsChange?(pins.count)
        onOverviewChange?()
    }

    private func movePin(_ touches: Set<UITouch>) {
        guard let held = pinHolder, touches.contains(held.touch), held.pin < pins.count else { return }
        pins[held.pin] = pixelLocation(held.touch)
        // A tool resting on the pin lets go of it rather than be dragged along.
        pivots = pivots.filter { $0.value.pin != held.pin }
        pinsChanged()
    }

    /// One, two or three vanishing points.
    static let maxPins = 3

    // MARK: Sheets

    /// Lays a new grid sheet on the paper, a little apart from the last one. Returns its id.
    func addGridLayer(_ pattern: GridPattern) -> Int? {
        guard let sheet else { return nil }
        let count = layers.filter { if case .grid = $0.kind { true } else { false } }.count
        guard var pose = screenPose(at: CGPoint(x: 0.5, y: 0.5)) else { return nil }
        let step = Self.sheetCascadeMM * sheet.pixelsPerMillimeter * Double(count % 6)
        pose.center.x += step
        pose.center.y += step
        let layer = PaperLayer(id: nextLayerID, kind: .grid(pattern), pose: pose)
        nextLayerID += 1
        let size = layer.rasterSize(pixelsPerMillimeter: sheet.pixelsPerMillimeter)
        let make = { (shading: [UInt32]) in
            GraphiteSurface(sheet: DraftingSheet(width: size.width, height: size.height,
                                                 pixelsPerMillimeter: sheet.pixelsPerMillimeter,
                                                 paper: sheet.paper, historyBudgetBytes: DraftingSheet.defaultHistoryBudget / 8),
                            scale: self.scale, shading: shading)
        }
        let surface = make(GraphiteShading.lookup), copies = make(GraphiteShading.carbonLookup)
        layerSurfaces[layer.id] = surface
        layerCopies[layer.id] = copies
        layers.append(layer)
        showLayer(layer, surfaces: [copies, surface], sheet: sheet)
        layersChanged()
        return layer.id
    }

    /// Lays a new sheet of tone on the paper. Returns its id.
    func addToneLayer(_ pattern: TonePattern) -> Int? {
        guard let sheet, var pose = screenPose(at: CGPoint(x: 0.5, y: 0.5)) else { return nil }
        let count = layers.filter(\.kind.isTone).count
        let step = Self.sheetCascadeMM * sheet.pixelsPerMillimeter * Double(count % 6)
        pose.center.x -= step
        pose.center.y += step
        let layer = PaperLayer(id: nextLayerID, kind: .tone(pattern), pose: pose)
        nextLayerID += 1
        let (w, h) = layer.kind.sizeMM
        layers.append(layer)
        showLayer(layer, surfaces: [], sheet: sheet)
        setTone(layer.id, ToneCut(widthMM: w, heightMM: h))
        layersChanged()
        return layer.id
    }

    private func setTone(_ id: Int, _ cut: ToneCut) {
        toneCuts[id] = cut
        layerViews[id]?.showTone(cut)
    }

    /// A point on the paper in a sheet's own millimetres.
    private func sheetMillimetres(_ layer: PaperLayer, _ p: CGPoint) -> CGPoint {
        let ppmm = sheet?.pixelsPerMillimeter ?? 1
        let q = layer.surfacePoint(p, pixelsPerMillimeter: ppmm)
        return CGPoint(x: Double(q.x) / ppmm, y: Double(q.y) / ppmm)
    }

    /// Whether a sheet is there to be taken hold of at `p`: tone only where some is left.
    private func toneLeft(_ i: Int, near p: CGPoint) -> Bool {
        guard layers[i].kind.isTone else { return true }
        return toneCuts[layers[i].id]?.hasTone(near: sheetMillimetres(layers[i], p), radius: Self.gripMarginMM) ?? false
    }

    /// Cuts every sheet of tone along the knife's path so far.
    private func cut(along samples: [StrokeSample]) {
        guard cutting != nil else { return }
        var touched: Set<Int> = []
        for s in samples {
            if cutStart == nil { cutStart = s.location }
            defer { lastCut = s.location }
            guard let from = lastCut else { continue }
            for layer in layers where layer.kind.isTone && !hiddenLayers.contains(layer.id) {
                guard var tone = toneCuts[layer.id] else { continue }
                let before = tone
                if tone.cut(from: sheetMillimetres(layer, from), to: sheetMillimetres(layer, s.location)) {
                    if cutting?[layer.id] == nil { cutting?[layer.id] = before }
                    toneCuts[layer.id] = tone
                    touched.insert(layer.id)
                }
            }
        }
        for id in touched { if let tone = toneCuts[id] { layerViews[id]?.showTone(tone) } }
    }

    /// Lifts the cut-off piece of tone under a fingertip, from the top sheet with tone there.
    private func peel(at p: CGPoint) -> Bool {
        for layer in layers.reversed() where layer.kind.isTone && !hiddenLayers.contains(layer.id) {
            guard var tone = toneCuts[layer.id] else { continue }
            let q = sheetMillimetres(layer, p)
            guard tone.isKept(at: q) else { continue }
            let before = tone
            guard tone.peel(at: q) else { return false }
            setTone(layer.id, tone)
            undoStack.append(.tones([layer.id: (before, tone)]))
            redoStack.removeAll()
            notifyHistory()
            return true
        }
        return false
    }

    /// Empties the paper, or a grid sheet, of everything drawn on it: a fresh
    /// sheet for the next try. Copies the carbon made go too. One step to undo.
    @discardableResult
    func clearLayer(_ id: Int?) -> Bool {
        guard activeTouch == nil else { return false }
        let ids: [SurfaceID] = id.map { [.sheet($0), .sheetCopy($0)] } ?? [.paper, .carbonCopy]
        let cleared = ids.filter { surface($0)?.sheet.clear() == true }
        guard !cleared.isEmpty else { return false }
        undoStack.append(.marks(cleared))
        redoStack.removeAll()
        refresh()
        notifyHistory()
        return true
    }

    /// Presses a grid sheet onto the paper: what is drawn on it is printed
    /// where it lies now, as one step to undo. The sheet keeps its drawing.
    @discardableResult
    func stampLayer(_ id: Int) -> Bool {
        guard activeTouch == nil, let sheet, let source = layerSurfaces[id]?.sheet,
              let layer = layers.first(where: { $0.id == id }), !layer.kind.isTone, layer.kind != .carbon else { return false }
        let outline = layer.outline(pixelsPerMillimeter: sheet.pixelsPerMillimeter)
        let xs = outline.map { Double($0.x) }, ys = outline.map { Double($0.y) }
        let area = PixelRect(minX: Int(xs.min()!.rounded(.down)), minY: Int(ys.min()!.rounded(.down)),
                             maxX: Int(xs.max()!.rounded(.up)), maxY: Int(ys.max()!.rounded(.up)))
        let ppmm = sheet.pixelsPerMillimeter
        // Only the paper takes the print, and only under the sheet.
        let laid = sheet.imprint(source.graphite, over: area, mask: StrokeMask(inside: [outline, paperOutline], outside: [])) {
            layer.surfacePoint($0, pixelsPerMillimeter: ppmm)
        }
        guard laid else { return false }
        undoStack.append(.marks([.paper]))
        redoStack.removeAll()
        refresh()
        notifyHistory()
        return true
    }

    /// Takes a grid sheet off the paper, with what was drawn on it.
    func removeGridLayer(_ id: Int) {
        guard activeTouch == nil || !marking.contains(.sheet(id)) else { return }
        layers.removeAll { $0.id == id }
        layerViews.removeValue(forKey: id)?.removeFromSuperview()
        layerSurfaces[id] = nil
        layerCopies[id] = nil
        toneCuts[id] = nil
        layerHolders[id] = nil
        hiddenLayers.remove(id)
        undoStack = undoStack.compactMap { $0.without(id) }
        redoStack = redoStack.compactMap { $0.without(id) }
        layersChanged()
        notifyHistory()
    }

    /// Slips the carbon under everything on the paper, or takes it out.
    /// Once out it is a sheet like any other: it can be moved up over grid sheets.
    func setCarbon(onDesk: Bool) {
        guard let sheet else { return }
        let id = Self.carbonID
        guard onDesk else {
            layers.removeAll { $0.id == id }
            layerViews.removeValue(forKey: id)?.removeFromSuperview()
            layerHolders[id] = nil
            hiddenLayers.remove(id)
            layersChanged()
            return
        }
        guard !layers.contains(where: { $0.id == id }), let pose = screenPose(at: CGPoint(x: 0.5, y: 0.5)) else { return }
        let layer = PaperLayer(id: id, kind: .carbon, pose: pose)
        layers.insert(layer, at: 0)
        showLayer(layer, surfaces: [], sheet: sheet)
        layersChanged()
    }

    private func showLayer(_ layer: PaperLayer, surfaces: [GraphiteSurface], sheet: DraftingSheet) {
        let view = PaperLayerView(layer: layer, surfaces: surfaces, scale: scale, pixelsPerMillimeter: sheet.pixelsPerMillimeter)
        layerViews[layer.id] = view
        sheetsView.addSubview(view)
        view.place(layer, scale: scale)
    }

    /// Restacks the sheets' views in the order the sheets lie.
    private func layersChanged() {
        for layer in layers { if let view = layerViews[layer.id] { sheetsView.bringSubviewToFront(view) } }
        onLayersChange?(layers, hiddenLayers)
        onOverviewChange?()
    }

    /// Sets a sheet aside without taking it off, or brings it back.
    func setLayer(_ id: Int, hidden: Bool) {
        guard activeTouch == nil || !marking.contains(.sheet(id)) else { return }
        if hidden { hiddenLayers.insert(id) } else { hiddenLayers.remove(id) }
        layerViews[id]?.isHidden = hidden
        layerHolders[id] = nil
        layersChanged()
    }

    /// Moves a sheet one place up or down the stack.
    func shiftLayer(_ id: Int, up: Bool) {
        guard activeTouch == nil, let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i + 1 : i - 1
        guard layers.indices.contains(j) else { return }
        layers.swapAt(i, j)
        layersChanged()
    }

    /// A fingertip on a sheet's edge picks it up and lays it over the other grid sheets.
    /// One fingertip picks a sheet up by its edge. Two fingers pick it up
    /// anywhere on it, to move and turn it: a second finger joins one already
    /// holding the sheet, or one resting still on it.
    private func grabLayer(_ touch: UITouch, at point: CGPoint) -> Bool {
        guard let sheet else { return false }
        let ppmm = sheet.pixelsPerMillimeter
        let outer = Self.gripMarginMM * ppmm
        let visible = layers.indices.filter { !hiddenLayers.contains(layers[$0].id) }
        func onBody(_ i: Int, _ p: CGPoint) -> Bool {
            let outline = layers[i].outline(pixelsPerMillimeter: ppmm)
            return (Polygon.contains(p, outline) || Polygon.distance(p, to: outline) <= outer) && toneLeft(i, near: p)
        }

        // A second finger anywhere on a sheet one finger already holds.
        if let i = visible.last(where: { layerHolders[layers[$0].id, default: []].count == 1 && onBody($0, point) }) {
            layerHolders[layers[i].id]?.append((touch, point))
            return true
        }
        // By the edge.
        // (With the knife in hand a finger on tone peels it; two fingers still move it.)
        if let i = visible.last(where: {
            layers[$0].edgeBandContains(point, inner: Self.sheetGripMM * ppmm, outer: outer, pixelsPerMillimeter: ppmm)
                && layerHolders[layers[$0].id, default: []].isEmpty
                && toneLeft($0, near: point) && !(knifeInHand && layers[$0].kind.isTone)
        }) {
            hold(i, with: [(touch, point)])
            return true
        }
        // Two fingers resting together on the same sheet, the top one under both.
        for (other, start) in presses.still() where other != touch && other.phase != .ended && other.phase != .cancelled {
            guard let i = visible.last(where: { onBody($0, point) }), onBody(i, start),
                  visible.last(where: { onBody($0, start) }) == i,
                  layerHolders[layers[i].id, default: []].isEmpty else { continue }
            presses.cancel(other)
            hold(i, with: [(other, pixelLocation(other)), (touch, point)])
            return true
        }
        return false
    }

    private func hold(_ i: Int, with fingers: [(touch: UITouch, point: CGPoint)]) {
        let id = layers[i].id
        layerHolders[id] = fingers
        // A grid sheet comes up over the others; the carbon keeps its place, as it is slid about under things.
        if activeTouch == nil, layers[i].kind != .carbon {
            layers.append(layers.remove(at: i))
            layersChanged()
        }
    }

    private func moveLayers(_ touches: Set<UITouch>) {
        var moved = false
        for (id, held) in layerHolders where held.contains(where: { touches.contains($0.touch) }) {
            guard let i = layers.firstIndex(where: { $0.id == id }) else { continue }
            let now = held.map { pixelLocation($0.touch) }
            var pose = layers[i].pose
            switch held.count {
            case 1: pose = RigidMotion.slide(pose, from: held[0].point, to: now[0])
            default: pose = RigidMotion.slideAndTurn(pose, from: (held[0].point, held[1].point), to: (now[0], now[1]))
            }
            layers[i].pose = pose
            layerHolders[id] = zip(held, now).map { ($0.touch, $1) }
            layerViews[id]?.place(layers[i], scale: scale)
            moved = true
        }
        if moved { onOverviewChange?() }
    }

    /// The sheets as the pencil meets them.
    private func layerStack() -> LayerStack {
        guard let sheet else { return LayerStack() }
        let ppmm = sheet.pixelsPerMillimeter
        // Tone takes no pencil: the line goes onto whatever is under it.
        return LayerStack(sheets: layers.filter { !hiddenLayers.contains($0.id) && !$0.kind.isTone }.map {
            LayerStack.Sheet(id: $0.id, outline: $0.outline(pixelsPerMillimeter: ppmm), isCarbon: $0.kind == .carbon)
        }, paper: paperOutline)
    }

    private func surface(_ id: SurfaceID) -> GraphiteSurface? {
        switch id {
        case .paper: paperSurface
        case .carbonCopy: copySurface
        case .sheet(let i): layerSurfaces[i]
        case .sheetCopy(let i): layerCopies[i]
        }
    }

    private var allSurfaces: [GraphiteSurface] {
        [paperSurface, copySurface].compactMap { $0 } + Array(layerSurfaces.values) + Array(layerCopies.values)
    }

    /// A sample or mask on the paper, moved onto the surface it marks.
    private func onSurface(_ id: SurfaceID) -> ((CGPoint) -> CGPoint, (StrokeSample) -> StrokeSample) {
        let sheetID: Int? = switch id {
        case .sheet(let i), .sheetCopy(let i): i
        case .paper, .carbonCopy: nil
        }
        guard let i = sheetID, let sheet, let layer = layers.first(where: { $0.id == i }) else { return ({ $0 }, { $0 }) }
        let ppmm = sheet.pixelsPerMillimeter
        return ({ layer.surfacePoint($0, pixelsPerMillimeter: ppmm) }, { layer.surfaceSample($0, pixelsPerMillimeter: ppmm) })
    }

    static let carbonID = 0
    /// How far in from its edge a fingertip still picks up a sheet.
    private static let sheetGripMM = 12.0
    /// Each new grid sheet lies this much further down and right.
    private static let sheetCascadeMM = 10.0

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
    /// The pencil marks whatever lies on top where it goes, and presses through the carbon.
    private func startStroke(_ touch: UITouch, erasing: Bool, from start: CGPoint? = nil, event: UIEvent?) {
        guard let sheet else { return }
        activeTouch = touch
        pending = PendingSampleQueue()
        lastPredicted = []
        let grade = currentGrade()
        markingGrade = grade
        lastWorn = nil
        marking = []
        markingErases = erasing
        recorder = StrokeRecorder(pixelsPerMillimeter: sheet.pixelsPerMillimeter)
        recordStarted = (.now, CACurrentMediaTime())
        if knifeInHand, !erasing {
            // The knife: follows the tools like the pencil, but cuts tone and leaves no line.
            cutting = [:]
            lastCut = nil
            cutStart = nil
            guide = makeGuide(startingAt: sample(touch).location, grade: grade, sheet: sheet)
            notifyHistory()
            feed(touch, event: event)
            return
        }
        for (id, mask) in layerStack().targets(erasing: erasing) {
            guard let target = surface(id)?.sheet else { continue }
            let local = mask.mapped(onSurface(id).0)
            if erasing { target.beginErasing(mask: local, kind: eraserKind) } else { target.beginStroke(grade: grade, mask: local) }
            marking.append(id)
        }
        if erasing {
            var tracker = RubTracker(pixelsPerMillimeter: sheet.pixelsPerMillimeter)
            if let start { lay([tracker.track(StrokeSample(location: start))], predicted: []) }
            guide = .rub(tracker)
        } else {
            guide = makeGuide(startingAt: sample(touch).location, grade: grade, sheet: sheet)
        }
        notifyHistory()
        feed(touch, event: event)
    }

    /// Lays samples on the paper into every surface the stroke is marking.
    private func lay(_ samples: [StrokeSample], predicted: [StrokeSample]) {
        if cutting != nil {
            cut(along: samples)
            return
        }
        var samples = samples, predicted = predicted
        if !markingErases { wear(&samples, predicted: &predicted) }
        if let raw = pendingRaw, raw.count == samples.count { recorder?.add(pencil: raw, line: samples) }
        pendingRaw = nil
        // A sheet held while drawing moves its edge under the pencil.
        let masks = layerHolders.isEmpty ? nil : Dictionary(layerStack().targets(erasing: markingErases).map { ($0.surface, $0.mask) },
                                                            uniquingKeysWith: { a, _ in a })
        for id in marking {
            guard let target = surface(id)?.sheet else { continue }
            let (point, sample) = onSurface(id)
            if let mask = masks?[id] { target.setStrokeMask(mask.mapped(point)) }
            target.extendStroke(with: samples.map(sample), predicted: predicted.map(sample))
        }
        refresh()
    }

    /// Appends the stroke just finished to Documents/strokes.jsonl, one JSON
    /// object a line, so its feel can be measured off the iPad
    /// (`xcrun devicectl device copy from … --domain-type appDataContainer`).
    private func logStroke() {
        guard let recorder, !recorder.pencil.isEmpty else { return }
        self.recorder = nil
        let kind: String = if cutting != nil { "knife" } else {
            switch guide {
            case .edge: "edge"
            case .arc: "arc"
            case .rub: "rub"
            case nil: "free"
            }
        }
        let record = recorder.record(guide: kind, grade: currentGrade().label, tools: tools.map(\.kind.rawValue),
                                     startedAt: recordStarted.date, seconds: CACurrentMediaTime() - recordStarted.time)
        Self.logQueue.async { Self.append(record) }
    }

    private static let logQueue = DispatchQueue(label: "Jedo.strokeLog", qos: .utility)

    nonisolated private static func append(_ record: StrokeRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(record),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        line.append(0x0A)
        let url = folder.appendingPathComponent("strokes.jsonl")
        // Keep it small: past 8 MB the log starts again, the last one kept beside it.
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 8 << 20 {
            let old = folder.appendingPathComponent("strokes.old.jsonl")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    /// Lays the stroke down on every surface it marked, as one step to undo.
    private func finishMarking() {
        logStroke()
        if let before = cutting {
            cutting = nil
            defer { lastCut = nil; cutStart = nil }
            // A knife merely touched down cuts nothing. (In the simulator, where
            // there is no lone fingertip, that click peels instead.)
            if let start = cutStart, let end = lastCut, let sheet,
               hypot(Double(end.x - start.x), Double(end.y - start.y)) < sheet.pixelsPerMillimeter {
                for (id, old) in before { setTone(id, old) }
                if Self.mouseDraws { _ = peel(at: end) }
                return
            }
            var changes: [Int: (before: ToneCut, after: ToneCut)] = [:]
            for (id, old) in before { if let now = toneCuts[id], now != old { changes[id] = (old, now) } }
            if !changes.isEmpty {
                undoStack.append(.tones(changes))
                redoStack.removeAll()
            }
            return
        }
        let changed = marking.filter { surface($0)?.sheet.endStroke() == true }
        marking = []
        if !changed.isEmpty {
            undoStack.append(.marks(changed))
            redoStack.removeAll()
        }
    }

    private func cancelMarking() {
        recorder = nil
        if let before = cutting {
            for (id, old) in before { setTone(id, old) }
            cutting = nil
            lastCut = nil
            cutStart = nil
        }
        for id in marking { surface(id)?.sheet.cancelStroke() }
        marking = []
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
            } else if knifeInHand, activeTouch == nil, peel(at: point) {
                continue
            } else if isDeliberateFinger(touch) {
                onFingerTouch?()
            }
        }
    }

    /// A fingertip on the paper while the pencil is idle, not a palm resting as you draw.
    private func isDeliberateFinger(_ touch: UITouch) -> Bool {
        guard !Self.mouseDraws, !eraserInHand, !knifeInHand, touch.type == .direct, activeTouch == nil else { return false }
        let pencilIdle = CACurrentMediaTime() - lastPencilActivity > Self.palmGrace
        return pencilIdle && touch.majorRadius < Self.fingertipRadius
    }

    /// Palms keep landing for a while after a stroke ends.
    private static let palmGrace: CFTimeInterval = 3
    /// Contact radius, in points, above which a touch is a palm or side of the hand.
    /// A fingertip pressed and held flat reads up to about 40.
    private static let fingertipRadius: CGFloat = 45

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        movePin(touches)
        moveTools(touches)
        moveLayers(touches)
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
        if let touch = activeTouch, touches.contains(touch) {
            feed(touch, event: event, predicting: false)
            // Whatever is still estimated goes in as it is; the pencil has lifted.
            extend(with: pending.flush())
            finishMarking()
            activeTouch = nil
            finishCompassStroke(drew: true)
            refresh()
            notifyHistory()
        }
        fingersLifted(touches.filter { $0 != pencil }, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let pencil = activeTouch
        if let touch = activeTouch, touches.contains(touch) {
            cancelMarking()
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
        var final = released
        var ahead = pending.provisional + lastPredicted
        if var guide {
            final = guide.guide(released, tools: toolShapes)
            self.guide = guide
            pendingRaw = released
            var lookahead = guide
            ahead = lookahead.guide(ahead, tools: toolShapes)
            if let angle = lookahead.arc?.angle, var compass {
                compass.leadAngle = angle
                self.compass = compass
                showCompass()
            }
        }
        lay(final, predicted: ahead)
    }

    private func pixelLocation(_ touch: UITouch) -> CGPoint {
        let p = touch.preciseLocation(in: self)
        return CGPoint(x: p.x * scale, y: p.y * scale)
    }

    private static func awaitsForce(_ touch: UITouch) -> Bool {
        touch.type == .pencil && touch.estimatedPropertiesExpectingUpdates.contains(.force)
    }

    // MARK: Lead point

    /// Wears the point by the line just drawn, and gives every sample the
    /// bluntness of the side touching the paper.
    private func wear(_ samples: inout [StrokeSample], predicted: inout [StrokeSample]) {
        guard let sheet else { return }
        var lead = leads[markingGrade] ?? LeadPoint()
        for i in samples.indices {
            if let last = lastWorn {
                lead.draw(last.distance(to: samples[i].location) / sheet.pixelsPerMillimeter,
                          pressure: samples[i].pressure, grade: markingGrade, roll: roll)
            }
            lastWorn = samples[i].location
            samples[i].bluntness = lead.bluntness(roll: roll)
        }
        let now = lead.bluntness(roll: roll)
        for i in predicted.indices { predicted[i].bluntness = now }
        let before = leads[markingGrade]?.worst ?? 0
        leads[markingGrade] = lead
        // Report in steps, not every sample.
        if Int(lead.worst * 20) != Int(before * 20) { onLeadChange?(markingGrade, lead.worst) }
    }

    /// Back to a fine point.
    func sharpen(_ grade: PencilGrade) {
        leads[grade] = LeadPoint()
        onLeadChange?(grade, 0)
    }

    /// Turns the pencil in hand a sixth, for pencils that can't sense it.
    func turnPencil() {
        let grade = currentGrade()
        var lead = leads[grade] ?? LeadPoint()
        lead.turn()
        leads[grade] = lead
        onLeadChange?(grade, lead.worst)
    }

    private func sample(_ touch: UITouch) -> StrokeSample {
        let point = touch.preciseLocation(in: self)
        let isPencil = touch.type == .pencil
        // Apple Pencil Pro reports the barrel's roll; other pencils report none (0).
        if isPencil, touch.rollAngle != 0 { roll = Double(touch.rollAngle) }
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
        for surface in allSurfaces { surface.refresh() }
    }

    static let noAnimations: [String: CAAction] = [
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

extension CanvasView: UIPencilInteractionDelegate {
    /// A double-tap turns the pencil a sixth in the hand, so a fresh side of
    /// the point touches the paper (Apple Pencil Pro senses the turn itself).
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard roll == nil else { return }
        turnPencil()
    }
}
