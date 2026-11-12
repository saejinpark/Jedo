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
        view.onLayersChange = { [weak session] layers, hidden in session?.layersChanged(layers, hidden: hidden) }
        view.compassStyle = session.compassStyle
        view.eraserKind = session.eraserKind
        view.onPinsChange = { [weak session] count in session?.pinsChanged(count) }
        view.onLeadChange = { [weak session] grade, wear in session?.leadChanged(grade, wear: wear) }
        session.canvas = view
        session.desk = controller.desk
        return controller
    }

    func updateUIViewController(_ controller: PaperDeskController, context: Context) {}
}
