import SwiftUI

struct CanvasRepresentable: UIViewRepresentable {
    let session: DrawingSession

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.currentGrade = { [weak session] in session?.grade ?? .hb }
        view.onHistoryChange = { [weak session] canUndo, canRedo in
            session?.historyChanged(canUndo: canUndo, canRedo: canRedo)
        }
        view.onFingerTouch = { [weak session] in session?.fingerTouchedPaper() }
        session.canvas = view
        return view
    }

    func updateUIView(_ view: CanvasView, context: Context) {}
}
