import Observation
import SwiftUI

/// What the SwiftUI shell and the canvas share: the lead in hand and the undo state.
@MainActor
@Observable
final class DrawingSession {
    var grade: PencilGrade = .hb
    /// The drawing paper, chosen once at the start.
    private(set) var paper: PaperSize?
    /// Tools lying on the paper.
    private(set) var toolsOnDesk: Set<ToolKind> = []
    /// Transparent grid sheets lying on the paper, bottom first.
    private(set) var gridSheets: [GridSheet] = []

    struct GridSheet: Identifiable {
        let id: Int
        let pattern: GridPattern
    }

    /// The sheets on the paper as the layers panel shows them, top first.
    private(set) var layerRows: [LayerRow] = []

    struct LayerRow: Identifiable, Equatable {
        let id: Int
        let name: String
        let isCarbon: Bool
        let hidden: Bool
        /// Whether it can go up or down a place (the carbon stays at the bottom).
        let canRaise: Bool
        let canLower: Bool
    }
    /// Whether the carbon lies under everything, copying what is pressed above it.
    var carbonOnDesk = false {
        didSet { canvas?.setCarbon(onDesk: carbonOnDesk) }
    }
    /// Millimetre scales of the paper along the screen's edges.
    var edgeRulers = true {
        didSet { desk?.showsRulers = edgeRulers }
    }
    /// Whether the hand holds the eraser, so a finger rubbing the paper erases.
    var eraserInHand = false {
        didSet {
            canvas?.eraserInHand = eraserInHand
            if eraserInHand { show(.eraser) }
        }
    }
    /// Whether the compass is out, so a finger held still plants its needle.
    var compassOnDesk = false {
        didSet {
            canvas?.setCompass(onDesk: compassOnDesk)
            if compassOnDesk { show(.compass) }
        }
    }
    /// The compass handling draft being tried.
    var compassStyle: CompassStyle = .firstDraft {
        didSet { canvas?.compassStyle = compassStyle }
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

        var text: String {
            switch self {
            case .pencil: "선은 Apple Pencil로 긋습니다. 손가락으로는 자를 잡고 컴퍼스 바늘을 꽂습니다."
            case .compass: "손가락으로 종이를 길게 누르면 그 자리에 컴퍼스 바늘이 꽂힙니다."
            case .eraser: "손가락으로 문지르면 지워집니다. 펜슬은 그대로 긋습니다."
            }
        }

        var symbol: String {
            switch self {
            case .pencil: "applepencil.tip"
            case .compass: "compass.drawing"
            case .eraser: "eraser"
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

    /// Lays the drawing paper on the desk.
    func start(on paper: PaperSize) {
        guard self.paper == nil else { return }
        self.paper = paper
        canvas?.start(on: paper)
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
        guard let id = canvas?.addGridLayer(pattern) else { return }
        gridSheets.append(GridSheet(id: id, pattern: pattern))
    }

    /// Takes a grid sheet away, with what was drawn on it.
    func removeSheet(_ id: Int) {
        canvas?.removeGridLayer(id)
        gridSheets.removeAll { $0.id == id }
    }

    func setLayer(_ id: Int, hidden: Bool) { canvas?.setLayer(id, hidden: hidden) }
    func shiftLayer(_ id: Int, up: Bool) { canvas?.shiftLayer(id, up: up) }

    /// Takes a sheet off the paper: a grid sheet with what was drawn on it, or the carbon.
    func removeLayer(_ id: Int) {
        if id == CanvasView.carbonID { carbonOnDesk = false } else { removeSheet(id) }
    }

    func layersChanged(_ layers: [PaperLayer], hidden: Set<Int>) {
        layerRows = layers.enumerated().reversed().map { i, layer in
            LayerRow(id: layer.id, name: Self.name(of: layer, among: layers), isCarbon: layer.kind == .carbon,
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
