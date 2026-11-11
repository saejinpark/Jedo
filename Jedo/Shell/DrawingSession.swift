import Observation
import SwiftUI

/// What the SwiftUI shell and the canvas share: the lead in hand and the undo state.
@MainActor
@Observable
final class DrawingSession {
    var grade: PencilGrade = .hb
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// Shown briefly when a finger touches the paper.
    private(set) var showsPencilHint = false

    @ObservationIgnored weak var canvas: CanvasView?
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private var hintsShown = 0
    /// Enough to learn the rule without nagging.
    static let maxHintsPerLaunch = 3

    func undo() { canvas?.undo() }
    func redo() { canvas?.redo() }

    func historyChanged(canUndo: Bool, canRedo: Bool) {
        if self.canUndo != canUndo { self.canUndo = canUndo }
        if self.canRedo != canRedo { self.canRedo = canRedo }
    }

    func fingerTouchedPaper() {
        guard !showsPencilHint, hintsShown < Self.maxHintsPerLaunch else { return }
        hintsShown += 1
        showsPencilHint = true
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.showsPencilHint = false
        }
    }
}
