import UIKit

/// Holds the sheet the way a desk holds paper: when the iPad turns, the
/// interface turns with it but the sheet does not move under the hand.
///
/// The canvas is a square centred on the screen. On every interface rotation
/// it is turned back by the same quarter turn, inside the same animation, so
/// on the glass it stays exactly where it was.
final class PaperDeskController: UIViewController {
    let canvas = CanvasView()
    private var turns = QuarterTurns(0)

    override func loadView() {
        view = PaperDeskView(canvas: canvas)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let interfaceTurn = QuarterTurns(approximating: coordinator.targetTransform)
        guard interfaceTurn.count != 0 else { return }
        turns = turns + -interfaceTurn
        let target = turns.transform
        coordinator.animate(alongsideTransition: { [canvas] _ in
            canvas.transform = target
            canvas.center = CGPoint(x: size.width / 2, y: size.height / 2)
        })
    }
}

final class PaperDeskView: UIView {
    let canvas: CanvasView

    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        backgroundColor = canvas.backgroundColor
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Bounds and centre, never frame: the canvas may be turned.
        let side = canvas.sideInPoints ?? max(bounds.width, bounds.height)
        canvas.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        canvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}
