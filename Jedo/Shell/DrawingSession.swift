import Observation
import SwiftUI

/// What the SwiftUI shell and the canvas share: the lead in hand and the undo state.
@MainActor
@Observable
final class DrawingSession {
    var grade: PencilGrade = .hb
    /// Tools lying on the paper.
    private(set) var toolsOnDesk: Set<ToolKind> = []
    /// Transparent grid sheets lying on the paper, bottom first.
    private(set) var gridSheets: [GridSheet] = []

    struct GridSheet: Identifiable {
        let id: Int
        let pattern: GridPattern
    }
    /// Whether the carbon lies under everything, copying what is pressed above it.
    var carbonOnDesk = false {
        didSet { canvas?.setCarbon(onDesk: carbonOnDesk) }
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
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private var hintsShown: [Hint: Int] = [:]
    /// Enough to learn the rule without nagging.
    static let maxHintsPerLaunch = 3

    func toggle(_ kind: ToolKind) {
        let onDesk = !toolsOnDesk.contains(kind)
        if onDesk { toolsOnDesk.insert(kind) } else { toolsOnDesk.remove(kind) }
        canvas?.setTool(kind, onDesk: onDesk)
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

    /// How a grid sheet is called in the menu: its pattern, numbered when there are several.
    func sheetName(_ id: Int) -> String {
        guard let sheet = gridSheets.first(where: { $0.id == id }) else { return "" }
        let same = gridSheets.filter { $0.pattern == sheet.pattern }
        guard same.count > 1, let n = same.firstIndex(where: { $0.id == id }) else { return sheet.pattern.name }
        return "\(sheet.pattern.name) \(n + 1)"
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
