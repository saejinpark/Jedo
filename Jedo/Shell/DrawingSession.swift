import Observation
import SwiftUI

/// What the SwiftUI shell and the canvas share: the lead in hand and the undo state.
@MainActor
@Observable
final class DrawingSession {
    var grade: PencilGrade = .hb
    /// What holds the lead: drafting mechanical pencils for lines, a wood pencil for shading.
    var instrument: Instrument = .mechanical(.mm05) {
        didSet {
            // Taking up a pencil, pen or roller puts the knife down: the pencil does one thing at a time.
            if knifeInHand { knifeInHand = false }
            if instrument == .stylus, oldValue != .stylus { show(.stylus) }
            if instrument == .roller, oldValue != .roller { show(.roller) }
        }
    }
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
        /// Whether it has a print that can be stamped with it.
        let hasPrint: Bool
        /// For carbon: its coating.
        let carbonInk: CarbonInk?
        let isPhoto: Bool
        /// A photo used as carbon.
        let photoCarbon: Bool
        /// Glued to the paper.
        let glued: Bool
        /// The sheet's symbol in the panel.
        let symbol: String
        let hidden: Bool
        /// Whether it can go up or down a place (the carbon stays at the bottom).
        let canRaise: Bool
        let canLower: Bool
    }
    /// Whether the carbon lies under everything, copying what is pressed above it.
    /// Lays a sheet of carbon in this coating.
    func addCarbon(_ ink: CarbonInk) { canvas?.addCarbonLayer(ink) }

    /// Lays a picture as carbon: pressed through, it gives its colours.
    func addPhotoCarbon(_ data: Data) {
        guard let photo = PhotoStore.add(data) else { return }
        _ = canvas?.addPhotoLayer(photo, asCarbon: true)
    }
    /// Which face of the triangular scale is up: 1:100·1:200, 1:300·1:400 or 1:500·1:600.
    var scaleFace = 0 {
        didSet {
            canvas?.scaleFace = scaleFace
            canvas?.setScaleFace(scaleFace)
        }
    }
    /// Whether the paper's map sits top right rather than top left.
    /// Where the map's grid squares start on the screen, as the arrangement puts them.
    var mapOrigin: CGPoint? {
        didSet { if mapOrigin != oldValue { desk?.mapOrigin = mapOrigin } }
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
    /// Whether `tool` is what the pencil works as now: not while the knife is in hand.
    func holds(_ tool: Instrument) -> Bool { instrument == tool && !knifeInHand }

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
        /// The stylus was picked up.
        case stylus
        /// The roller was picked up.
        case roller
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
            case .roller: "롤러는 먹지 위를 굴릴 때만 찍힙니다. 굴린 폭 30mm만큼 먹지 색이 밑으로 옮겨지고, 세게 누를수록 진합니다."
            case .stylus: "철필은 흑연 없이 홈만 냅니다. 그 위를 연필로 칠하면 홈이 하얗게 남습니다. 홈은 지우개로 문지르면 펴집니다."
            case .spotTaken: "그 자리에는 다른 도구가 있습니다. 빈 곳을 누르거나 그 도구를 먼저 치우세요."
            case .knife: "종이를 가로질러 그으면 갈라지고, 한 바퀴 돌려 처음 자리로 오면 그 모양대로 오려집니다. 톤은 눕혀 문지르면 긁힙니다."
            }
        }

        var symbol: String {
            switch self {
            case .pencil: "applepencil.tip"
            case .compass: "compass.drawing"
            case .eraser: "eraser"
            case .knife: "scissors.badge.ellipsis"
            case .place: "hand.point.down"
            case .roller: "paintbrush.pointed"
            case .stylus: "pencil.tip"
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

    #if DEBUG
    /// For trying whole drawings through the real engine: `-JedoScript name`
    /// draws Documents/name.json and writes the paper to Documents/name.png.
    /// `-JedoPace seconds` draws it slowly enough to watch, the view following the pen.
    func runScriptIfAsked() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-JedoScript"), i + 1 < args.count,
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: folder.appendingPathComponent(args[i + 1] + ".json")),
              let script = try? JSONDecoder().decode(DrawingScript.self, from: data),
              let series = PaperSize.Series.allCases.first(where: { "\($0)" == script.paper }) else { return false }
        canvas?.discardDrawing()
        paper = PaperSize(series: series, landscape: script.landscape)
        canvas?.start(on: paper!)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let at = script.photoAt.map { CGPoint(x: $0[0], y: $0[1]) }
            if let name = script.photo, let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
               let photo = PhotoStore.add(data), let id = canvas?.addPhotoLayer(photo), let at {
                canvas?.placeLayer(id, centreMM: at)
            }
            if script.tracing == true, let id = canvas?.addGridLayer(.tracing), let at {
                canvas?.placeLayer(id, centreMM: at)
            }
            canvas?.selectSheet(nil)
            let pace = args.firstIndex(of: "-JedoPace").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }
            let began = Date()
            var slowest = 0.0
            var slowestStep = ""
            var notes: [String] = []
            var asleep = 0.0
            for stroke in script.strokes {
                let t = Date()
                let sleptBefore = asleep
                defer {
                    let took = Date().timeIntervalSince(t) - (asleep - sleptBefore)
                    if took > slowest { (slowest, slowestStep) = (took, stroke.op ?? stroke.i) }
                }
                if let op = stroke.op {
                    // What the other hand does: pins, tools, tone, the knife.
                    let at = stroke.pts.map { CGPoint(x: $0[0], y: $0[1]) }
                    if pace != nil, let first = at.first, op != "pins" { desk?.follow(mm: first) }
                    switch op {
                    case "pins": canvas?.scriptPins(at)
                    case "tool":
                        if let kind = ToolKind(rawValue: stroke.k ?? ""), let p = stroke.pts.first {
                            canvas?.scriptTool(kind, centreMM: at[0], angle: p.count > 2 ? p[2] : 0)
                        }
                    case "untool": if let kind = ToolKind(rawValue: stroke.k ?? "") { canvas?.setTool(kind, onDesk: false) }
                    case "tone":
                        let pattern = TonePattern.allCases.first { "\($0)" == stroke.k } ?? .dots30
                        if let id = canvas?.addToneLayer(pattern), let p = stroke.pts.first {
                            canvas?.placeLayer(id, centreMM: at[0], angle: p.count > 2 ? p[2] : 0)
                            canvas?.selectSheet(nil)
                        }
                    case "carbon":
                        let ink = CarbonInk(rawValue: stroke.k ?? "") ?? .navy
                        if let id = canvas?.addCarbonLayer(ink), let p = stroke.pts.first {
                            canvas?.placeLayer(id, centreMM: at[0], angle: p.count > 2 ? p[2] : 0)
                            canvas?.selectSheet(nil)
                        }
                    case "photo", "photocarbon":
                        if let data = try? Data(contentsOf: folder.appendingPathComponent(stroke.k ?? "")), let photo = PhotoStore.add(data),
                           let id = canvas?.addPhotoLayer(photo, asCarbon: op == "photocarbon"), let p = stroke.pts.first {
                            canvas?.placeLayer(id, centreMM: at[0], angle: p.count > 2 ? p[2] : 0)
                            canvas?.selectSheet(nil)
                        } else { notes.append("no photo \(stroke.k ?? "")") }
                    case "slice": if canvas?.scriptSlice(at) == 0 { notes.append("nothing sliced from \(at[0])") }
                    case "lift": if canvas?.scriptLift(atMM: at[0]) != true { notes.append("nothing to lift at \(at[0])") }
                    case "glue": if canvas?.scriptGlue(atMM: at[0]) != true { notes.append("nothing to glue at \(at[0])") }
                    case "cut": canvas?.scriptKnife(at, scrape: false)
                    case "scrape": canvas?.scriptKnife(at, scrape: true, pressure: stroke.pts[0].count > 2 ? stroke.pts[0][2] : 0.6)
                    case "peel": if let p = at.first, canvas?.scriptPeel(atMM: p) != true { notes.append("nothing to peel at \(p)") }
                    default: break
                    }
                    if let pace {
                        let nap = pace * (op == "tool" ? 5 : 12)
                        try? await Task.sleep(for: .seconds(nap))
                        asleep += nap
                    }
                    continue
                }
                guard let instrument = DrawingScript.instrument(stroke.i) else { continue }
                if let pace, let first = stroke.pts.first {
                    // Slowly, for watching: the view follows the pen.
                    desk?.follow(mm: CGPoint(x: first[0], y: first[1]))
                    let nap = pace * (1 + Double(stroke.pts.count) / 10)
                    try? await Task.sleep(for: .seconds(nap))
                    asleep += nap
                }
                let grade = PencilGrade.allCases.first { $0.label == stroke.g } ?? .hb
                canvas?.draw(stroke.pts.map {
                    CanvasView.RecordedPoint(x: $0[0], y: $0[1], pressure: $0.count > 2 ? $0[2] : 0.5,
                                             altitude: $0.count > 3 ? $0[3] : .pi / 2)
                }, grade: grade, instrument: instrument)
            }
            let drew = Date().timeIntervalSince(began) - asleep
            try? await Task.sleep(for: .seconds(0.5))
            let exportBegan = Date()
            let report = { (exported: Double) in
let text = String(format: "strokes %d, drawing %.2f s (%.2f ms a stroke, slowest %.1f ms: %@), export %.2f s\n",
                                  script.strokes.count, drew, drew / Double(max(script.strokes.count, 1)) * 1000, slowest * 1000, slowestStep, exported)
                    + notes.map { $0 + "\n" }.joined()
                try? text.write(to: folder.appendingPathComponent(args[i + 1] + ".txt"), atomically: true, encoding: .utf8)
            }
            defer { report(Date().timeIntervalSince(exportBegan)) }
            if let image = canvas?.exportImage(includeSheets: true), let png = image.pngData() {
                try? png.write(to: folder.appendingPathComponent(args[i + 1] + ".png"))
            }
        }
        return true
    }

    struct DrawingScript: Decodable {
        struct Stroke: Decodable {
            /// m03 m05 m07 m09 wood g maru p013 p018 p025 p035 p05 p07 p10
            var i: String
            var g: String?
            /// Not a stroke but a step of the other hand: pins, tool [x, y, angle], untool, tone [x, y, angle],
            /// cut, scrape, peel (tone); carbon, photo, photocarbon [x, y, angle]; slice, lift, glue (loose sheets).
            /// `k` names the tool, the tone, the carbon's ink or the picture's file.
            var op: String?
            var k: String?
            /// [x mm, y mm, pressure?, altitude?]
            var pts: [[Double]]
        }
        var paper: String
        var landscape: Bool
        var strokes: [Stroke]
        /// A picture in Documents to lay as a print, centred at `photoAt` (mm), and tracing paper over it.
        var photo: String?
        var photoAt: [Double]?
        var tracing: Bool?

        static func instrument(_ code: String) -> Instrument? {
            switch code {
            case "m03": .mechanical(.mm03)
            case "m05": .mechanical(.mm05)
            case "m07": .mechanical(.mm07)
            case "m09": .mechanical(.mm09)
            case "wood": .wood
            case "stylus": .stylus
            case "roller": .roller
            case "g": .dipPen(.gPen)
            case "maru": .dipPen(.maru)
            case "p013": .technicalPen(.w013)
            case "p018": .technicalPen(.w018)
            case "p025": .technicalPen(.w025)
            case "p035": .technicalPen(.w035)
            case "p05": .technicalPen(.w05)
            case "p07": .technicalPen(.w07)
            case "p10": .technicalPen(.w10)
            default: nil
            }
        }
    }
    #endif

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
    func stampLayer(_ id: Int, withPrint: Bool = false) { canvas?.stampLayer(id, withPrint: withPrint) }

    func setLayer(_ id: Int, hidden: Bool) { canvas?.setLayer(id, hidden: hidden) }

    /// Whether the list of layers lies open on the screen.
    var layersOpen = false
    /// The sheet picked out on the desk, whose bar of actions shows.
    var selectedSheet: Int?
    var selectedRow: LayerRow? { selectedSheet.flatMap { id in layerRows.first { $0.id == id } } }

    func selectSheet(_ id: Int?) { canvas?.selectSheet(id) }
    func flipLayer(_ id: Int, leftRight: Bool) { canvas?.flipLayer(id, leftRight: leftRight) }

    /// Lays a picture from the photo library on the desk as a print.
    func addPhoto(_ data: Data) {
        guard let photo = PhotoStore.add(data) else { return }
        _ = canvas?.addPhotoLayer(photo)
    }

    /// Lays the first page of a PDF on the desk as a print at its real size.
    func addPDF(at url: URL) {
        guard let page = PhotoStore.addPDF(at: url) else { return }
        _ = canvas?.addPhotoLayer(page)
    }

    func glueLayer(_ id: Int) { canvas?.glueLayer(id) }
    func setPhotoCarbon(_ id: Int, _ on: Bool) { canvas?.setPhotoCarbon(id, on) }
    func shiftLayer(_ id: Int, up: Bool) { canvas?.shiftLayer(id, up: up) }

    /// Takes a sheet off the paper: with what was drawn on it, or a piece of carbon.
    func removeLayer(_ id: Int) { removeSheet(id) }

    /// What the next carbon laid is coated with.
    var carbonInk: CarbonInk = .navy {
        didSet { canvas?.carbonInk = carbonInk }
    }

    func setCarbonInk(_ id: Int, _ ink: CarbonInk) {
        carbonInk = ink
        canvas?.setCarbonInk(id, ink)
    }

    /// Whether any tone lies on the paper.
    var hasTone: Bool { layerRows.contains(where: \.isTone) }
    /// Whether anything lies on the paper for the knife: tone, or a sheet of paper to cut in pieces.
    var canCut: Bool { !layerRows.filter { !$0.glued }.isEmpty }

    func layersChanged(_ layers: [PaperLayer], hidden: Set<Int>) {
        defer { if !canCut, knifeInHand { knifeInHand = false } }
        layerRows = layers.enumerated().reversed().map { i, layer in
            LayerRow(id: layer.id, name: Self.name(of: layer, among: layers), isCarbon: layer.kind == .carbon,
                     isTone: layer.kind.isTone,
                     canStamp: layer.kind.takesPencil && !layer.glued && !layer.photoCarbon,
                     hasPrint: { if case .grid(let p) = layer.kind { !p.isPlain } else { false } }(),
                     carbonInk: layer.kind == .carbon ? layer.carbonInk : nil,
                     isPhoto: layer.kind.photo != nil, photoCarbon: layer.photoCarbon, glued: layer.glued,
                     symbol: layer.kind.photo != nil ? (layer.glued ? "photo.fill" : "photo") : layer.kind == .carbon ? "square.fill" : layer.kind.isTone ? "circle.grid.3x3.fill"
                        : { if case .grid(let p) = layer.kind, p.isPlain { "doc.plaintext" } else { "squareshape.split.3x3" } }(),
                     hidden: hidden.contains(layer.id),
                     // Glued photos stay at the bottom, part of the paper; loose sheets stay over them.
                     canRaise: !layer.glued && i < layers.count - 1,
                     canLower: !layer.glued && i > layers.prefix(while: \.glued).count)
        }
    }

    /// A sheet's pattern, numbered in the order they were laid when there are several alike.
    private static func name(of layer: PaperLayer, among layers: [PaperLayer]) -> String {
        if layer.kind.photo != nil {
            let photos = layers.filter { $0.kind.photo != nil }.map(\.id).sorted()
            let n = (photos.firstIndex(of: layer.id) ?? 0) + 1
            return layer.glued ? "사진 \(n) (붙임)" : layer.photoCarbon ? "사진 \(n) (먹지)" : "사진 \(n)"
        }
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
