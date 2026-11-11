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
    /// Called when a finger touches the paper away from any tool.
    var onFingerTouch: (() -> Void)?

    /// The ruler, if it is on the paper. Canvas pixels.
    private(set) var ruler: Ruler?
    private let rulerView = RulerView()
    /// Fingers holding the ruler, oldest first, with where each was last (canvas pixels).
    private var holders: [(touch: UITouch, point: CGPoint)] = []
    private var guide: EdgeGuide?
    private let inkLayer = CALayer()

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
        layer.addSublayer(inkLayer)
        addSubview(rulerView)
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
        // A square sheet as long as the screen's long side. The desk keeps it
        // centred and turns it back when the interface turns.
        let side = Int(max(screen.nativeBounds.width, screen.nativeBounds.height).rounded(.up))
        let ppmm = DisplayDensity.pixelsPerMillimeter(nativeLongSidePixels: Double(side))
        let sheet = DraftingSheet(width: side, height: side, pixelsPerMillimeter: ppmm)
        self.sheet = sheet
        layPaper(for: sheet)
        superview?.setNeedsLayout()
        notifyHistory()
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
    }

    private func trimHistoryForMemoryWarning() {
        sheet?.trimHistory(toBytes: DraftingSheet.defaultHistoryBudget / 4)
        notifyHistory()
    }

    // MARK: Ruler

    /// Puts the ruler on the paper in the middle of the screen, lying level with
    /// the screen as it is now, or takes it away.
    func setRuler(onDesk: Bool) {
        guard let sheet else { return }
        guard onDesk else {
            ruler = nil
            holders.removeAll()
            rulerView.isHidden = true
            return
        }
        guard ruler == nil, let window else { return }
        let middle = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        let here = convert(middle, from: window)
        let right = convert(CGPoint(x: middle.x + 100, y: middle.y), from: window)
        let pose = RulerPose(center: CGPoint(x: here.x * scale, y: here.y * scale),
                             angle: atan2(Double(right.y - here.y), Double(right.x - here.x)))
        ruler = Ruler(pose: pose, pixelsPerMillimeter: sheet.pixelsPerMillimeter)
        showRuler()
    }

    private func showRuler() {
        guard let ruler, let sheet else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rulerView.show(ruler, scale: scale, pixelsPerMillimeter: sheet.pixelsPerMillimeter)
        CATransaction.commit()
    }

    /// A fingertip landing on (or just beside) the ruler takes hold of it.
    private func grabRuler(_ touch: UITouch) -> Bool {
        guard let ruler, let sheet, holders.count < 2, touch.majorRadius < Self.fingertipRadius else { return false }
        let point = pixelLocation(touch)
        guard ruler.contains(point, margin: Self.gripMarginMM * sheet.pixelsPerMillimeter) else { return false }
        holders.append((touch, point))
        return true
    }

    private func moveRuler() {
        guard var ruler, !holders.isEmpty else { return }
        let now = holders.map { pixelLocation($0.touch) }
        switch holders.count {
        case 1:
            ruler.pose = RigidMotion.slide(ruler.pose, from: holders[0].point, to: now[0])
        default:
            ruler.pose = RigidMotion.slideAndTurn(ruler.pose, from: (holders[0].point, holders[1].point), to: (now[0], now[1]))
        }
        for i in holders.indices { holders[i].point = now[i] }
        self.ruler = ruler
        showRuler()
    }

    private func releaseRuler(_ touches: Set<UITouch>) {
        holders.removeAll { touches.contains($0.touch) }
    }

    /// How far outside the ruler a fingertip still catches it.
    private static let gripMarginMM = 4.0

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
        for touch in touches where isFinger(touch, event) {
            if grabRuler(touch) { continue }
            if isDeliberateFinger(touch) { onFingerTouch?() }
        }
        guard activeTouch == nil, let sheet, let touch = touches.first(where: { draws($0, event) }) else { return }
        activeTouch = touch
        pending = PendingSampleQueue()
        let grade = currentGrade()
        guide = EdgeGuide(style: .standard, pixelsPerMillimeter: sheet.pixelsPerMillimeter,
                          contactOffset: grade.parameters.lineWidthMM / 2 * sheet.pixelsPerMillimeter)
        sheet.beginStroke(grade: grade)
        feed(touch, event: event)
    }

    /// A fingertip on the paper while the pencil is idle, not a palm resting as you draw.
    private func isDeliberateFinger(_ touch: UITouch) -> Bool {
        guard !Self.mouseDraws, touch.type == .direct, activeTouch == nil else { return false }
        let pencilIdle = CACurrentMediaTime() - lastPencilActivity > Self.palmGrace
        return pencilIdle && touch.majorRadius < Self.fingertipRadius
    }

    /// Palms keep landing for a while after a stroke ends.
    private static let palmGrace: CFTimeInterval = 3
    /// Contact radius, in points, above which a touch is a palm or side of the hand.
    private static let fingertipRadius: CGFloat = 30

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if holders.contains(where: { touches.contains($0.touch) }) { moveRuler() }
        guard let touch = activeTouch, touches.contains(touch) else { return }
        feed(touch, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseRuler(touches)
        guard let touch = activeTouch, touches.contains(touch), let sheet else { return }
        feed(touch, event: event, predicting: false)
        // Whatever is still estimated goes in as it is; the pencil has lifted.
        sheet.extendStroke(with: pending.flush(), predicted: [])
        sheet.endStroke()
        activeTouch = nil
        refresh()
        notifyHistory()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseRuler(touches)
        guard let touch = activeTouch, touches.contains(touch), let sheet else { return }
        sheet.cancelStroke()
        _ = pending.flush()
        activeTouch = nil
        refresh()
        notifyHistory()
    }

    /// Apple Pencil first reports force as an estimate and sends the measured
    /// value a moment later. Held-back samples are drawn as provisional until then.
    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        guard activeTouch != nil, let sheet else { return }
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
        sheet.extendStroke(with: released, predicted: pending.provisional + lastPredicted)
        refresh()
    }

    private func feed(_ touch: UITouch, event: UIEvent?, predicting: Bool = true) {
        guard let sheet else { return }
        lastPencilActivity = CACurrentMediaTime()
        var final: [StrokeSample] = []
        for coalesced in event?.coalescedTouches(for: touch) ?? [touch] {
            let key = Self.awaitsForce(coalesced) ? coalesced.estimationUpdateIndex : nil
            final += pending.append(guided(sample(coalesced)), awaitingUpdate: key)
        }
        // Predicted touches go through a copy of the guide, so they never change the real one.
        var lookahead = guide
        lastPredicted = predicting
            ? (event?.predictedTouches(for: touch) ?? []).map { lookahead?.guide(sample($0), ruler: ruler) ?? sample($0) }
            : []
        sheet.extendStroke(with: final, predicted: pending.provisional + lastPredicted)
        refresh()
    }

    /// Bends a sample onto the ruler's edge where the pencil meets it.
    private func guided(_ sample: StrokeSample) -> StrokeSample {
        guide?.guide(sample, ruler: ruler) ?? sample
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
