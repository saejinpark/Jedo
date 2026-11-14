import Observation
import SwiftUI

/// What the SwiftUI shell and the canvas share: the lead in hand and the undo state.
@MainActor
@Observable
final class DrawingSession {
    var grade: PencilGrade = .hb
    /// What holds the lead: drafting mechanical pencils for lines, a wood pencil for shading.
    var instrument: Instrument = .mechanical(.mm05)
    /// The drawing paper, chosen once at the start.
    private(set) var paper: PaperSize?
    /// Tools lying on the paper.
    private(set) var toolsOnDesk: Set<ToolKind> = []
    /// The sheets on the paper as the layers panel shows them, top first.
    private(set) var layerRows: [LayerRow] = []

    struct LayerRow: Identifiable, Equatable {
        let id: Int
        let name: String
        let isCarbon: Bool
        let isTone: Bool
        /// Whether it can be pressed onto the paper (grid sheets).
        let canStamp: Bool
        /// The sheet's symbol in the panel.
        let symbol: String
        let hidden: Bool
        /// Whether it can go up or down a place (the carbon stays at the bottom).
        let canRaise: Bool
        let canLower: Bool
    }
    /// Whether the carbon lies under everything, copying what is pressed above it.
    var carbonOnDesk = false {
        didSet { canvas?.setCarbon(onDesk: carbonOnDesk) }
    }
    /// Which face of the triangular scale is up: 1:100·1:200, 1:300·1:400 or 1:500·1:600.
    var scaleFace = 0 {
        didSet {
            canvas?.scaleFace = scaleFace
            canvas?.setScaleFace(scaleFace)
        }
    }
    /// Whether the paper's map sits top right rather than top left.
    var mapOnTrailing = false {
        didSet { desk?.mapOnTrailing = mapOnTrailing }
    }
    /// Millimetre scales of the paper along the screen's edges.
    var edgeRulers = true {
        didSet { desk?.showsRulers = edgeRulers }
    }
    /// Whether the hand holds the eraser, so a finger rubbing the paper erases.
    var eraserInHand = false {
        didSet {
            canvas?.eraserInHand = eraserInHand
            if eraserInHand {
                if knifeInHand { knifeInHand = false }
                show(.eraser)
            }
        }
    }
    /// How many perspective pins are in the board.
    private(set) var pinCount = 0

    func addPin() { canvas?.addPin() }
    func removePins() { canvas?.removePins() }
    func pinsChanged(_ count: Int) { if pinCount != count { pinCount = count } }

    /// Which eraser is in hand.
    var eraserKind: EraserKind = .rubber {
        didSet { canvas?.eraserKind = eraserKind }
    }
    /// Whether the hand holds the knife, so the pencil cuts tone and a finger peels it.
    var knifeInHand = false {
        didSet {
            canvas?.knifeInHand = knifeInHand
            if knifeInHand {
                if eraserInHand { eraserInHand = false }
                show(.knife)
            }
        }
    }
    /// Whether the compass is out, so a finger held still plants its needle.
    var compassOnDesk = false {
        didSet {
            canvas?.setCompass(onDesk: compassOnDesk)
            if compassOnDesk { show(.compass) }
        }
    }
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// A short line of help, shown for a moment.
    private(set) var hint: Hint?

    enum Hint: Hashable {
        /// A finger tried to draw.
        case pencil
        /// The compass just came out.
        case compass
        /// The eraser was picked up.
        case eraser
        /// The knife was picked up.
        case knife
        /// A tool was taken out and waits to be laid.
        case place(ToolKind)
        /// The spot pressed for it is taken.
        case spotTaken(ToolKind)

        var text: String {
            switch self {
            case .pencil: "선은 Apple Pencil로 긋습니다. 손가락으로는 자를 잡고 컴퍼스 바늘을 꽂습니다."
            case .compass: "손가락으로 종이를 길게 누르면 그 자리에 컴퍼스 바늘이 꽂힙니다."
            case .eraser: "손가락으로 문지르면 지워집니다. 펜슬은 그대로 긋습니다."
            case .place(let kind): "\(kind.name): 놓을 자리를 손가락으로 누르세요. 누른 채 끌어 맞춥니다."
            case .spotTaken: "그 자리에는 다른 도구가 있습니다. 빈 곳을 누르거나 그 도구를 먼저 치우세요."
            case .knife: "세워 그으면 톤이 잘리고, 종이를 끝에서 끝까지 가르면 두 조각이 됩니다. 눕혀 문지르면 망점이 긁혀 나갑니다."
            }
        }

        var symbol: String {
            switch self {
            case .pencil: "applepencil.tip"
            case .compass: "compass.drawing"
            case .eraser: "eraser"
            case .knife: "scissors"
            case .place: "hand.point.down"
            case .spotTaken: "exclamationmark.circle"
            }
        }
    }

    @ObservationIgnored weak var canvas: CanvasView?
    @ObservationIgnored weak var desk: PaperDeskView?
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private var hintsShown: [Hint: Int] = [:]
    /// Enough to learn the rule without nagging.
    static let maxHintsPerLaunch = 3

    func toggle(_ kind: ToolKind) {
        let onDesk = !toolsOnDesk.contains(kind)
        if onDesk { toolsOnDesk.insert(kind) } else { toolsOnDesk.remove(kind) }
        canvas?.setTool(kind, onDesk: onDesk)
    }

    /// A tool taken out, waiting to be laid where a finger presses.
    private(set) var toolInHand: ToolKind?

    func toolInHandChanged(_ kind: ToolKind?) {
        toolInHand = kind
        // Stays up until the tool is laid: it is what the hand is doing now.
        hintTask?.cancel()
        if let kind {
            hint = .place(kind)
        } else if case .place = hint {
            hint = nil
        }
    }

    /// The spot pressed is taken by another tool: say so, then go back to waiting.
    func toolSpotTaken(_ kind: ToolKind) {
        hintTask?.cancel()
        hint = .spotTaken(kind)
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled, let self, self.toolInHand == kind else { return }
            self.hint = .place(kind)
        }
    }

    /// A tool taken out and not laid, put back because another was taken.
    func toolPutBack(_ kind: ToolKind) { toolsOnDesk.remove(kind) }

    /// Lays the drawing paper on the desk.
    func start(on paper: PaperSize) {
        guard self.paper == nil else { return }
        self.paper = paper
        canvas?.start(on: paper)
    }

    /// Picks up the drawing left on the desk last time, if there is one.
    func resumeSaved() {
        guard paper == nil, let saved = DrawingStore.load() else { return }
        paper = saved.paper
        canvas?.resume(saved)
    }

    /// Throws the drawing away for good, so a fresh sheet can be laid.
    func throwAwayPaper() {
        canvas?.discardDrawing()
    }

    /// Saves the paper as a PNG and offers it to share or save: the paper
    /// alone, or with the sheets lying on it.
    func export(includeSheets: Bool) {
        guard let canvas, let image = canvas.exportImage(includeSheets: includeSheets),
              let data = image.pngData() else { return }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = format.string(from: .now)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("제도 \(stamp).png")
        do { try data.write(to: url, options: .atomic) } catch { return }
        guard let window = canvas.window, var top = window.rootViewController else { return }
        while let shown = top.presentedViewController { top = shown }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = share.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.maxX - 50, y: 40, width: 1, height: 1)
        }
        top.present(share, animated: true)
    }

    /// Lays a new grid sheet on the paper.
    func addSheet(_ pattern: GridPattern) {
        _ = canvas?.addGridLayer(pattern)
    }

    /// Lays a new sheet of tone on the paper.
    func addTone(_ pattern: TonePattern) {
        _ = canvas?.addToneLayer(pattern)
    }

    /// Takes a grid sheet away, with what was drawn on it.
    func removeSheet(_ id: Int) {
        canvas?.removeGridLayer(id)
    }

    /// Empties a grid sheet, or the paper with `nil`, for a fresh try.
    func clearLayer(_ id: Int?) { canvas?.clearLayer(id) }

    /// Prints a grid sheet's drawing onto the paper where it lies.
    func stampLayer(_ id: Int) { canvas?.stampLayer(id) }

    func setLayer(_ id: Int, hidden: Bool) { canvas?.setLayer(id, hidden: hidden) }
    func shiftLayer(_ id: Int, up: Bool) { canvas?.shiftLayer(id, up: up) }

    /// Takes a sheet off the paper: a grid sheet with what was drawn on it, or the carbon.
    func removeLayer(_ id: Int) {
        if id == CanvasView.carbonID { carbonOnDesk = false } else { removeSheet(id) }
    }

    /// Whether any tone lies on the paper.
    var hasTone: Bool { layerRows.contains(where: \.isTone) }
    /// Whether anything lies on the paper for the knife: tone, or a sheet of paper to cut in pieces.
    var canCut: Bool { layerRows.contains { $0.isTone || $0.canStamp } }

    func layersChanged(_ layers: [PaperLayer], hidden: Set<Int>) {
        defer { if !canCut, knifeInHand { knifeInHand = false } }
        let carbon = layers.contains { $0.kind == .carbon }
        if carbonOnDesk != carbon { carbonOnDesk = carbon }
        layerRows = layers.enumerated().reversed().map { i, layer in
            LayerRow(id: layer.id, name: Self.name(of: layer, among: layers), isCarbon: layer.kind == .carbon,
                     isTone: layer.kind.isTone,
                     canStamp: { if case .grid = layer.kind { true } else { false } }(),
                     symbol: layer.kind == .carbon ? "square.fill" : layer.kind.isTone ? "circle.grid.3x3.fill"
                        : { if case .grid(let p) = layer.kind, p.isPlain { "doc.plaintext" } else { "squareshape.split.3x3" } }(),
                     hidden: hidden.contains(layer.id), canRaise: i < layers.count - 1, canLower: i > 0)
        }
    }

    /// A sheet's pattern, numbered in the order they were laid when there are several alike.
    private static func name(of layer: PaperLayer, among layers: [PaperLayer]) -> String {
        let alike = layers.filter { $0.kind == layer.kind }.map(\.id).sorted()
        guard alike.count > 1, let n = alike.firstIndex(of: layer.id) else { return layer.kind.name }
        return "\(layer.kind.name) \(n + 1)"
    }

    func undo() { canvas?.undo() }
    func redo() { canvas?.redo() }

    func historyChanged(canUndo: Bool, canRedo: Bool) {
        if self.canUndo != canUndo { self.canUndo = canUndo }
        if self.canRedo != canRedo { self.canRedo = canRedo }
    }

    func fingerTouchedPaper() { show(.pencil) }

    private func show(_ hint: Hint) {
        guard self.hint == nil, hintsShown[hint, default: 0] < Self.maxHintsPerLaunch else { return }
        hintsShown[hint, default: 0] += 1
        self.hint = hint
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.hint = nil
        }
    }
}
