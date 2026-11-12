import Observation
import SwiftUI

/// What the SwiftUI shell and the canvas share: the lead in hand and the undo state.
@MainActor
@Observable
final class DrawingSession {
    var grade: PencilGrade = .hb
    /// Tools lying on the paper.
    private(set) var toolsOnDesk: Set<ToolKind> = []
    /// Graph paper instead of plain.
    var graphPaper = false {
        didSet { canvas?.setGraphPaper(graphPaper) }
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
