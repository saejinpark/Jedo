import SwiftUI

struct CanvasRepresentable: UIViewControllerRepresentable {
    let session: DrawingSession

    func makeUIViewController(context: Context) -> PaperDeskController {
        let controller = PaperDeskController()
        let view = controller.canvas
        view.currentGrade = { [weak session] in session?.grade ?? .hb }
        view.onHistoryChange = { [weak session] canUndo, canRedo in
            session?.historyChanged(canUndo: canUndo, canRedo: canRedo)
        }
        view.onFingerTouch = { [weak session] in session?.fingerTouchedPaper() }
        view.compassStyle = session.compassStyle
        view.eraserHand = session.eraserHand
        view.onPencilTap = { [weak session] in session?.pencilTapped() }
        session.canvas = view
        return controller
    }

    func updateUIViewController(_ controller: PaperDeskController, context: Context) {}
}
