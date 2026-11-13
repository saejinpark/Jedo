import CoreGraphics
import Foundation

/// The drawing paper, chosen when a drawing starts. It lies fixed on the
/// desk, the background everything else is laid on.
struct PaperSize: Hashable, Sendable {
    enum Series: CaseIterable, Hashable, Sendable {
        case a4, a3, a2, a1, a0
        case b5, b4, b3, b2, b1
        /// Exactly the screen: nothing to move about, so no map or stick.
        case screen

        static let aSizes: [Series] = [.a4, .a3, .a2, .a1, .a0]
        static let bSizes: [Series] = [.b5, .b4, .b3, .b2, .b1]
    }

    var series: Series
    var landscape: Bool
    /// For `.screen`: the screen's size in millimetres, as it was held when the paper was laid.
    var screenWidthMM = 0.0
    var screenHeightMM = 0.0

    var fitsScreen: Bool { series == .screen }

    var name: String {
        switch series {
        case .a4: "A4"
        case .a3: "A3"
        case .a2: "A2"
        case .a1: "A1"
        case .a0: "A0"
        case .b5: "B5"
        case .b4: "B4"
        case .b3: "B3"
        case .b2: "B2"
        case .b1: "B1"
        case .screen: "화면 맞춤"
        }
    }

    /// Width and height in millimetres, as it lies.
    var sizeMM: (width: Double, height: Double) {
        if series == .screen { return (screenWidthMM, screenHeightMM) }
        let (short, long): (Double, Double) = switch series {
        case .a4: (210, 297)
        case .a3: (297, 420)
        case .a2: (420, 594)
        case .a1: (594, 841)
        // The screen is only a window on it: the hand works an iPad's reach at a time, as on a big board.
        case .a0: (841, 1189)
        // The B sizes used for Korean drafting paper (KS, as JIS).
        case .b5: (182, 257)
        case .b4: (257, 364)
        case .b3: (364, 515)
        case .b2: (515, 728)
        case .b1: (728, 1030)
        case .screen: (screenWidthMM, screenHeightMM)
        }
        return landscape ? (long, short) : (short, long)
    }

    /// How much desk shows around the paper at most, each side.
    static let deskMarginMM = 60.0

    /// The square desk it lies on, in millimetres: room around the paper, and
    /// at least `minimumMM` across. Paper fitted to the screen has no room around it.
    func deskSideMM(minimumMM: Double) -> Double {
        let long = max(sizeMM.width, sizeMM.height)
        return max(fitsScreen ? long : long + 2 * Self.deskMarginMM, minimumMM)
    }
}

/// The printed pattern of a transparent grid sheet.
/// Every sheet laid over the drawing is tracing paper: plain, or with a grid
/// printed on it (as gridded tracing paper is sold). `GridPattern` is its print.
enum GridPattern: CaseIterable, Hashable, Sendable {
    /// Plain white tracing paper, A4: enough to trace a whole drawing.
    case tracing
    /// Yellow trace (버터지), torn from a 30 cm roll: thin, cheap, for
    /// laying one design idea over another.
    case butter
    /// 1 mm squares, 5 mm and 1 cm lines heavier.
    case square1
    /// 5 mm squares, every fifth line heavier, on a long sheet.
    case square5
    /// Isometric: three families of lines 5 mm apart, 60° to each other.
    case isometric
    /// A round sheet: rings every 5 mm and a ray every 15°.
    case polar
    var name: String {
        switch self {
        case .square1: "모눈 방안 1mm"
        case .square5: "모눈 방안 5mm"
        case .isometric: "모눈 등각 5mm"
        case .polar: "모눈 극좌표"
        case .tracing: "트레이싱지 A4"
        case .butter: "버터지"
        }
    }

    /// Width and height of the sheet in millimetres.
    var sizeMM: (width: Double, height: Double) {
        switch self {
        case .square1: (120, 120)
        case .square5: (140, 100)
        case .isometric: (110, 110)
        case .polar: (120, 120)
        case .tracing: (210, 297)
        case .butter: (300, 300)
        }
    }

    var isRound: Bool { self == .polar }

    /// Nothing printed on it.
    var isPlain: Bool { self == .tracing || self == .butter }
}

/// A sheet that lies on the paper and moves with the hand: a transparent
/// grid sheet the pencil marks, or the carbon at the bottom that copies
/// what is pressed above it onto the paper.
enum SheetKind: Hashable, Sendable {
    case grid(GridPattern)
    case carbon
    /// Screen tone: printed film that is cut with the knife and peeled.
    /// The pencil passes it by; it is laid over a drawing.
    case tone(TonePattern)

    /// A sheet of tone, as cut from a larger one.
    static let toneSizeMM = (width: 120.0, height: 100.0)

    var isTone: Bool { if case .tone = self { true } else { false } }

    /// Cut smaller than the screen, so its edges stay in reach.
    static let carbonSizeMM = (width: 120.0, height: 170.0)

    var sizeMM: (width: Double, height: Double) {
        switch self {
        case .grid(let pattern): pattern.sizeMM
        case .carbon: Self.carbonSizeMM
        case .tone: Self.toneSizeMM
        }
    }

    var name: String {
        switch self {
        case .grid(let pattern): pattern.name
        case .carbon: "먹지"
        case .tone(let pattern): "톤 · \(pattern.name)"
        }
    }

    /// Outline in millimetres, centred on the sheet.
    var outlineMM: [CGPoint] {
        let (w, h) = sizeMM
        if case .grid(let pattern) = self, pattern.isRound {
            let r = w / 2
            return (0..<Self.roundSegments).map { i in
                let a = Double(i) / Double(Self.roundSegments) * 2 * .pi
                return CGPoint(x: r * cos(a), y: r * sin(a))
            }
        }
        return [CGPoint(x: -w / 2, y: -h / 2), CGPoint(x: w / 2, y: -h / 2),
                CGPoint(x: w / 2, y: h / 2), CGPoint(x: -w / 2, y: h / 2)]
    }

    static let roundSegments = 128
}

/// One sheet lying on the paper.
struct PaperLayer: Identifiable, Equatable, Sendable {
    let id: Int
    var kind: SheetKind
    /// Centre and turn, in paper pixels.
    var pose: ToolPose

    /// Pixels of the sheet's own drawing surface, which moves with it.
    func rasterSize(pixelsPerMillimeter ppmm: Double) -> (width: Int, height: Int) {
        let (w, h) = kind.sizeMM
        return (Int((w * ppmm).rounded(.up)), Int((h * ppmm).rounded(.up)))
    }

    /// The outline on the paper, in paper pixels.
    func outline(pixelsPerMillimeter ppmm: Double) -> [CGPoint] {
        kind.outlineMM.map { world(CGPoint(x: Double($0.x) * ppmm, y: Double($0.y) * ppmm)) }
    }

    /// A point on the paper in the sheet's own pixels, from its top-left corner.
    func surfacePoint(_ p: CGPoint, pixelsPerMillimeter ppmm: Double) -> CGPoint {
        let dx = Double(p.x - pose.center.x), dy = Double(p.y - pose.center.y)
        let c = cos(pose.angle), s = sin(pose.angle)
        let (w, h) = kind.sizeMM
        return CGPoint(x: dx * c + dy * s + w * ppmm / 2, y: -dx * s + dy * c + h * ppmm / 2)
    }

    /// A point in the sheet's own pixels, back on the paper.
    func paperPoint(fromSurface q: CGPoint, pixelsPerMillimeter ppmm: Double) -> CGPoint {
        let (w, h) = kind.sizeMM
        let u = Double(q.x) - w * ppmm / 2, v = Double(q.y) - h * ppmm / 2
        let c = cos(pose.angle), s = sin(pose.angle)
        return CGPoint(x: Double(pose.center.x) + u * c - v * s, y: Double(pose.center.y) + u * s + v * c)
    }

    /// A pencil sample as it lands on the sheet's own surface.
    func surfaceSample(_ sample: StrokeSample, pixelsPerMillimeter ppmm: Double) -> StrokeSample {
        var s = sample
        s.location = surfacePoint(sample.location, pixelsPerMillimeter: ppmm)
        s.azimuth -= pose.angle
        return s
    }

    /// Whether a fingertip at `p` takes hold of the sheet: on its edge, from
    /// `outer` outside it to `inner` inside it. The middle stays free for the
    /// eraser and the compass needle.
    func edgeBandContains(_ p: CGPoint, inner: Double, outer: Double, pixelsPerMillimeter ppmm: Double) -> Bool {
        let outline = outline(pixelsPerMillimeter: ppmm)
        let distance = Polygon.distance(p, to: outline)
        return Polygon.contains(p, outline) ? distance <= inner : distance <= outer
    }

    private func world(_ q: CGPoint) -> CGPoint {
        let c = cos(pose.angle), s = sin(pose.angle)
        return CGPoint(x: Double(pose.center.x) + Double(q.x) * c - Double(q.y) * s,
                       y: Double(pose.center.y) + Double(q.x) * s + Double(q.y) * c)
    }
}

/// Which surface a pencil or eraser stroke lands on.
enum SurfaceID: Hashable, Sendable {
    /// The drawing paper itself.
    case paper
    /// What carbon has copied onto the paper.
    case carbonCopy
    /// A grid sheet's own surface.
    case sheet(Int)
    /// What carbon has copied onto a grid sheet lying under it.
    case sheetCopy(Int)
}

/// The soft sheets on the paper, for routing a stroke. The paper is the
/// background; on it lie grid sheets and carbon in any order. The pencil
/// marks whatever is on top where it is, and pressing through the carbon
/// copies onto whatever lies just under it. Rigid tools are not here; they
/// never take a mark.
struct LayerStack: Sendable {
    struct Sheet: Sendable {
        var id: Int
        var outline: [CGPoint]
        var isCarbon: Bool
    }

    /// Bottom first.
    var sheets: [Sheet] = []
    /// The drawing paper's outline; nothing marks the desk beyond it.
    var paper: [CGPoint]?

    init(sheets: [Sheet] = [], paper: [CGPoint]? = nil) {
        self.sheets = sheets
        self.paper = paper
    }

    /// Where a sheet's drawing is copied when it is stamped: at each point,
    /// onto whatever lies just under it that takes pencil: the next tracing
    /// sheet down, or where there is none, the paper. Carbon in between takes
    /// no part (it is not drawn on). Masks are on the paper.
    func stampTargets(from source: Int) -> [(surface: SurfaceID, mask: StrokeMask)] {
        guard let i = sheets.firstIndex(where: { $0.id == source }) else { return [] }
        let outline = sheets[i].outline
        let below = sheets[..<i].enumerated().filter { !$0.element.isCarbon }
        var out: [(SurfaceID, StrokeMask)] = []
        for (j, sheet) in below {
            // Under the source, on this sheet, and not under a sheet between them.
            let between = below.filter { $0.offset > j }.map(\.element.outline)
            out.append((.sheet(sheet.id), StrokeMask(inside: [outline, sheet.outline], outside: between)))
        }
        let onPaper = paper.map { [$0] } ?? []
        out.append((.paper, StrokeMask(inside: [outline] + onPaper, outside: below.map(\.element.outline))))
        return out
    }

    /// Every surface the stroke may mark, and where on the paper it may.
    func targets(erasing: Bool) -> [(surface: SurfaceID, mask: StrokeMask)] {
        var out: [(SurfaceID, StrokeMask)] = []
        // Graphite: on whatever is on top. Carbon takes no graphite worth keeping.
        for (i, sheet) in sheets.enumerated() where !sheet.isCarbon {
            let reach = StrokeMask(inside: [sheet.outline], outside: sheets[(i + 1)...].map(\.outline))
            out.append((.sheet(sheet.id), reach))
            // Copies on a sheet are rubbed out where the sheet is bare.
            if erasing { out.append((.sheetCopy(sheet.id), reach)) }
        }
        let onPaper = paper.map { [$0] } ?? []
        let bare = StrokeMask(inside: onPaper, outside: sheets.map(\.outline))
        out.append((.paper, bare))
        if erasing {
            out.append((.carbonCopy, bare))
        } else if let c = sheets.lastIndex(where: \.isCarbon) {
            // Pressing through the topmost carbon copies onto what lies just under it.
            let carbon = sheets[c].outline
            for i in sheets.indices where i < c && !sheets[i].isCarbon {
                out.append((.sheetCopy(sheets[i].id),
                            StrokeMask(inside: [carbon, sheets[i].outline], outside: sheets[(i + 1)..<c].map(\.outline))))
            }
            out.append((.carbonCopy, StrokeMask(inside: [carbon] + onPaper, outside: sheets[..<c].map(\.outline))))
        }
        return out
    }
}

/// Where a stroke may mark a surface: within every `inside` polygon and
/// none of the `outside` ones. Polygons are convex, which keeps telling
/// whether a dab is wholly in or out quick.
struct StrokeMask: Sendable {
    var inside: [[CGPoint]]
    var outside: [[CGPoint]]
    /// Plates lying over the surface with openings in them (the erasing
    /// shield): under a plate, only its openings can be reached.
    var shields: [Shield] = []

    struct Shield: Sendable {
        var outline: [CGPoint]
        var openings: [[CGPoint]]

        func allows(_ p: CGPoint) -> Bool {
            !Polygon.contains(p, outline) || openings.contains { Polygon.contains(p, $0) }
        }
    }

    init(inside: [[CGPoint]], outside: [[CGPoint]], shields: [Shield] = []) {
        self.inside = inside
        self.outside = outside
        self.shields = shields
    }

    static let everywhere = StrokeMask(inside: [], outside: [])

    var isEverywhere: Bool { inside.isEmpty && outside.isEmpty && shields.isEmpty }

    enum Coverage: Equatable { case none, all, part }

    func contains(_ p: CGPoint) -> Bool {
        inside.allSatisfy { Polygon.contains(p, $0) } && !outside.contains { Polygon.contains(p, $0) }
            && shields.allSatisfy { $0.allows(p) }
    }

    /// How much of a pixel rectangle the stroke may mark.
    func coverage(_ rect: PixelRect) -> Coverage {
        guard !isEverywhere else { return .all }
        var all = true
        for polygon in inside {
            switch Polygon.classify(rect, polygon) {
            case .outside: return .none
            case .part: all = false
            case .inside: break
            }
        }
        for polygon in outside {
            switch Polygon.classify(rect, polygon) {
            case .inside: return .none
            case .part: all = false
            case .outside: break
            }
        }
        for shield in shields {
            switch Polygon.classify(rect, shield.outline) {
            case .outside: break
            case .inside, .part:
                let places = shield.openings.map { Polygon.classify(rect, $0) }
                if places.contains(.inside) { break }
                let covered = Polygon.classify(rect, shield.outline) == .inside
                if covered, places.allSatisfy({ $0 == .outside }) { return .none }
                all = false
            }
        }
        return all ? .all : .part
    }

    /// The mask in another frame, as when moving onto a sheet's own surface.
    func mapped(_ transform: (CGPoint) -> CGPoint) -> StrokeMask {
        StrokeMask(inside: inside.map { $0.map(transform) }, outside: outside.map { $0.map(transform) },
                   shields: shields.map { Shield(outline: $0.outline.map(transform), openings: $0.openings.map { $0.map(transform) }) })
    }
}

/// Small geometry on plain point lists.
enum Polygon {
    enum Placement: Equatable { case inside, outside, part }

    /// Even–odd inside test.
    static func contains(_ p: CGPoint, _ polygon: [CGPoint]) -> Bool {
        var result = false
        var j = polygon.count - 1
        let px = Double(p.x), py = Double(p.y)
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (Double(a.y) > py) != (Double(b.y) > py) {
                let x = Double(a.x) + (py - Double(a.y)) / Double(b.y - a.y) * Double(b.x - a.x)
                if px < x { result.toggle() }
            }
            j = i
        }
        return result
    }

    /// Distance from `p` to the polygon's outline.
    static func distance(_ p: CGPoint, to polygon: [CGPoint]) -> Double {
        var best = Double.infinity
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let ex = Double(b.x - a.x), ey = Double(b.y - a.y)
            let lengthSquared = ex * ex + ey * ey
            let t = lengthSquared > 0 ? min(max((Double(p.x - a.x) * ex + Double(p.y - a.y) * ey) / lengthSquared, 0), 1) : 0
            best = min(best, hypot(Double(p.x) - Double(a.x) - ex * t, Double(p.y) - Double(a.y) - ey * t))
        }
        return best
    }

    /// Where a pixel rectangle lies against a convex polygon.
    static func classify(_ rect: PixelRect, _ polygon: [CGPoint]) -> Placement {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        if corners.allSatisfy({ contains($0, polygon) }) { return .inside }
        // Separated along an axis of the rectangle or of the polygon: wholly outside.
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for q in polygon {
            minX = min(minX, Double(q.x)); maxX = max(maxX, Double(q.x))
            minY = min(minY, Double(q.y)); maxY = max(maxY, Double(q.y))
        }
        if maxX <= Double(rect.minX) || minX >= Double(rect.maxX) || maxY <= Double(rect.minY) || minY >= Double(rect.maxY) {
            return .outside
        }
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let nx = Double(b.y - a.y), ny = -Double(b.x - a.x)
            let project = { (q: CGPoint) in Double(q.x) * nx + Double(q.y) * ny }
            var lo = Double.infinity, hi = -Double.infinity
            for q in polygon { let v = project(q); lo = min(lo, v); hi = max(hi, v) }
            let r = corners.map(project)
            if r.max()! <= lo || r.min()! >= hi { return .outside }
        }
        return .part
    }
}

/// The lines printed on a grid sheet, in millimetres from its top-left corner.
enum GridRulings {
    enum Weight: Int, CaseIterable, Sendable { case fine, medium, bold }

    struct Line: Equatable, Sendable {
        var from: CGPoint
        var to: CGPoint
        var weight: Weight
    }

    struct Ring: Equatable, Sendable {
        var radius: Double
        var weight: Weight
    }

    static func lines(_ pattern: GridPattern) -> [Line] {
        let (w, h) = pattern.sizeMM
        switch pattern {
        case .square1:
            return square(width: w, height: h, step: 1) { $0 % 10 == 0 ? .bold : $0 % 5 == 0 ? .medium : .fine }
        case .square5:
            return square(width: w, height: h, step: 5) { $0 % 5 == 0 ? .medium : .fine }
        case .isometric:
            return isometric(width: w, height: h, spacing: 5)
        case .tracing, .butter:
            return []
        case .polar:
            let r = w / 2
            return stride(from: 0, to: 360, by: 15).map { degrees in
                let a = Double(degrees) * .pi / 180
                let weight: Weight = degrees % 90 == 0 ? .bold : degrees % 45 == 0 ? .medium : .fine
                return Line(from: CGPoint(x: r, y: r), to: CGPoint(x: r + r * cos(a), y: r + r * sin(a)), weight: weight)
            }
        }
    }

    static func rings(_ pattern: GridPattern) -> [Ring] {
        guard pattern == .polar else { return [] }
        let r = pattern.sizeMM.width / 2
        return stride(from: 5.0, through: r, by: 5).map { radius in
            let n = Int((radius / 5).rounded())
            return Ring(radius: radius, weight: n % 10 == 0 ? .bold : n % 5 == 0 ? .medium : .fine)
        }
    }

    /// Lines every `step` mm; `weight` gets the line's count from the edge.
    private static func square(width: Double, height: Double, step: Double, weight: (Int) -> Weight) -> [Line] {
        var out: [Line] = []
        for i in 0...Int((width / step).rounded(.down)) {
            let x = Double(i) * step
            out.append(Line(from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: height), weight: weight(i)))
        }
        for i in 0...Int((height / step).rounded(.down)) {
            let y = Double(i) * step
            out.append(Line(from: CGPoint(x: 0, y: y), to: CGPoint(x: width, y: y), weight: weight(i)))
        }
        return out
    }

    /// Verticals and lines at ±30° from the horizontal, `spacing` apart, clipped to the sheet.
    private static func isometric(width: Double, height: Double, spacing: Double) -> [Line] {
        var out: [Line] = []
        let centre = (x: width / 2, y: height / 2)
        let reach = hypot(width, height) / 2
        for degrees in [90.0, 30.0, -30.0] {
            let a = degrees * .pi / 180
            let dir = (x: cos(a), y: sin(a)), normal = (x: -sin(a), y: cos(a))
            let count = Int((reach / spacing).rounded(.up))
            for k in -count...count {
                let o = Double(k) * spacing
                let base = (x: centre.x + normal.x * o, y: centre.y + normal.y * o)
                guard let (t0, t1) = clip(base, dir, width: width, height: height), t1 - t0 > 0.01 else { continue }
                out.append(Line(from: CGPoint(x: base.x + dir.x * t0, y: base.y + dir.y * t0),
                                to: CGPoint(x: base.x + dir.x * t1, y: base.y + dir.y * t1),
                                weight: k % 5 == 0 ? .medium : .fine))
            }
        }
        return out
    }

    /// The span of the line `base + t·dir` inside the rectangle (Liang–Barsky).
    private static func clip(_ base: (x: Double, y: Double), _ dir: (x: Double, y: Double),
                             width: Double, height: Double) -> (Double, Double)? {
        var t0 = -Double.infinity, t1 = Double.infinity
        for (p, d, lo, hi) in [(base.x, dir.x, 0.0, width), (base.y, dir.y, 0.0, height)] {
            if abs(d) < 1e-12 {
                if p < lo || p > hi { return nil }
            } else {
                let a = (lo - p) / d, b = (hi - p) / d
                t0 = max(t0, min(a, b))
                t1 = min(t1, max(a, b))
            }
        }
        return t0 < t1 ? (t0, t1) : nil
    }
}
