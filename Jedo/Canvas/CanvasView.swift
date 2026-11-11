import UIKit

/// The sheet of paper on screen. Apple Pencil draws; fingers are left for
/// the drafting tools that come in later milestones.
///
/// Paper is a grid of layers sharing one texture image. Graphite sits above
/// it in 128-pixel tiles that are created when first drawn on and redrawn
/// only where they changed.
final class CanvasView: UIView {
    /// Read at the start of every stroke, so a lead picked a moment ago is always the one used.
    var currentGrade: () -> PencilGrade = { .hb }
    /// Called after every change to what can be undone or redone.
    var onHistoryChange: ((_ canUndo: Bool, _ canRedo: Bool) -> Void)?
    /// Called when a finger touches the paper, which does not draw.
    var onFingerTouch: (() -> Void)?

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
        // A square sheet as long as the screen's long side, so turning the iPad
        // never cuts off a drawing.
        let side = Int(max(screen.nativeBounds.width, screen.nativeBounds.height).rounded(.up))
        let ppmm = DisplayDensity.pixelsPerMillimeter(nativeLongSidePixels: Double(side))
        let sheet = DraftingSheet(width: side, height: side, pixelsPerMillimeter: ppmm)
        self.sheet = sheet
        layPaper(for: sheet)
        notifyHistory()
    }

    private func layPaper(for sheet: DraftingSheet) {
        paperLayers.forEach { $0.removeFromSuperlayer() }
        paperLayers.removeAll()
        let texture = sheet.paper
        guard let image = Self.makeImage(pixels: GraphiteShading.paperPixels(texture), width: texture.size, height: texture.size) else { return }
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

    // MARK: Touches

    private func draws(_ touch: UITouch) -> Bool {
        touch.type == .pencil || (Self.mouseDraws && touch.type == .direct)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.contains(where: isDeliberateFinger) { onFingerTouch?() }
        guard activeTouch == nil, let sheet, let touch = touches.first(where: draws) else { return }
        activeTouch = touch
        pending = PendingSampleQueue()
        sheet.beginStroke(grade: currentGrade())
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
        guard let touch = activeTouch, touches.contains(touch) else { return }
        feed(touch, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
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
            final += pending.append(sample(coalesced), awaitingUpdate: key)
        }
        lastPredicted = predicting ? (event?.predictedTouches(for: touch) ?? []).map(sample) : []
        sheet.extendStroke(with: final, predicted: pending.provisional + lastPredicted)
        refresh()
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
        self.layer.addSublayer(layer)
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
