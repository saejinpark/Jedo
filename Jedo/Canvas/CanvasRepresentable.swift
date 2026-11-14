import SwiftUI

struct CanvasRepresentable: UIViewControllerRepresentable {
    let session: DrawingSession

    func makeUIViewController(context: Context) -> PaperDeskController {
        let controller = PaperDeskController()
        let view = controller.canvas
        view.currentGrade = { [weak session] in session?.grade ?? .hb }
        view.currentInstrument = { [weak session] in session?.instrument ?? .mechanical(.mm05) }
        view.onHistoryChange = { [weak session] canUndo, canRedo in
            session?.historyChanged(canUndo: canUndo, canRedo: canRedo)
        }
        view.onFingerTouch = { [weak session] in session?.fingerTouchedPaper() }
        view.onLayersChange = { [weak session] layers, hidden in session?.layersChanged(layers, hidden: hidden) }
        view.eraserKind = session.eraserKind
        view.onPinsChange = { [weak session] count in session?.pinsChanged(count) }
        view.onToolInHandChange = { [weak session] kind in session?.toolInHandChanged(kind) }
        view.onToolPutBack = { [weak session] kind in session?.toolPutBack(kind) }
        view.onToolSpotTaken = { [weak session] kind in session?.toolSpotTaken(kind) }
        view.onSheetSelect = { [weak session] id in session?.selectedSheet = id }
        session.canvas = view
        session.desk = controller.desk
        controller.desk.mapOrigin = session.mapOrigin
        #if DEBUG
        if session.runScriptIfAsked() { return controller }
        #endif
        session.resumeSaved()
        return controller
    }

    func updateUIViewController(_ controller: PaperDeskController, context: Context) {}
}
