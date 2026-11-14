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
    /// Korean manuscript paper (원고지), 200 squares: rows of 20 with a strip between rows.
    case manuscript
    /// Japanese manuscript paper (genkō yōshi), 400 squares written in columns,
    /// with the fold strip down the middle.
    case genkou
    /// Comic manuscript paper, B4: the trim, bleed and inner frame printed in
    /// non-photo blue, with crop marks.
    case manga
    /// The squared exercise book of Korean first graders (깍두기 공책): large
    /// squares with a dotted cross for placing each letter.
    case squareBook
    /// Music staff paper (오선지).
    case staff
    /// English four-line paper: the third line, the base line, in red.
    case fourLine
    var name: String {
        switch self {
        case .manuscript: "원고지 200자"
        case .genkou: "원고지 400자 (세로)"
        case .manga: "만화 원고용지 B4"
        case .squareBook: "깍두기 공책"
        case .staff: "오선지"
        case .fourLine: "영어 4선 공책"
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
        case .manuscript: (180, 127)
        case .genkou: (226, 180)
        case .manga: (257, 364)
        case .squareBook: (160, 216)
        case .staff, .fourLine: (210, 297)
        }
    }

    /// Ruled tracing (모눈) as against the printed writing and manuscript papers.
    var isGraph: Bool { [.square1, .square5, .isometric, .polar].contains(self) }

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
    /// A photo print: drawn on like paper, cut, glued down, or used as carbon.
    case photo(PhotoRef)

    /// Whether the pencil draws on it, so it has a surface of its own.
    var takesPencil: Bool {
        switch self {
        case .grid, .photo: true
        case .carbon, .tone: false
        }
    }

    var photo: PhotoRef? { if case .photo(let p) = self { p } else { nil } }

    /// A sheet of tone, as cut from a larger one.
    static let toneSizeMM = (width: 120.0, height: 100.0)

    var isTone: Bool { if case .tone = self { true } else { false } }

    /// Cut smaller than the screen, so its edges stay in reach.
    static let carbonSizeMM = (width: 120.0, height: 170.0)

    var sizeMM: (width: Double, height: Double) {
        switch self {
        case .grid(let pattern): pattern.sizeMM
        case .photo(let p): (p.widthMM, p.heightMM)
        case .carbon: Self.carbonSizeMM
        case .tone: Self.toneSizeMM
        }
    }

    var name: String {
        switch self {
        case .grid(let pattern): pattern.name
        case .photo: "사진"
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
    /// What is left of the sheet after the knife, in millimetres about the
    /// whole sheet's centre; nil while it is uncut. The surface stays the
    /// whole sheet's size, so a piece keeps its drawing where it was.
    var pieceMM: [CGPoint]? = nil
    /// For carbon: what it is coated with.
    var carbonInk: CarbonInk = .navy
    /// Turned over left to right, or top to bottom: what is drawn on it shows
    /// through mirrored, as tracing paper turned over does.
    var flippedX = false
    var flippedY = false

    /// A photo used as carbon: what is pressed through it comes out in its colours.
    var photoCarbon = false
    /// Glued down to the paper (collage): it no longer moves, and is part of the paper.
    var glued = false

    /// Whether pressing through it copies onto what lies under it.
    var isCarbon: Bool { kind == .carbon || (photoCarbon && kind.photo != nil) }

    /// The same sheet under another id: a piece cut from it.
    func piece(id: Int, outline: [CGPoint]) -> PaperLayer {
        PaperLayer(id: id, kind: kind, pose: pose, pieceMM: outline, carbonInk: carbonInk, flippedX: flippedX, flippedY: flippedY,
                   photoCarbon: photoCarbon, glued: glued)
    }

    private var mirror: (x: Double, y: Double) { (flippedX ? -1 : 1, flippedY ? -1 : 1) }

    /// The sheet's outline in millimetres about its centre: the piece, or the whole sheet.
    var outlineMM: [CGPoint] { pieceMM ?? kind.outlineMM }

    /// Pixels of the sheet's own drawing surface, which moves with it.
    func rasterSize(pixelsPerMillimeter ppmm: Double) -> (width: Int, height: Int) {
        let (w, h) = kind.sizeMM
        return (Int((w * ppmm).rounded(.up)), Int((h * ppmm).rounded(.up)))
    }

    /// The outline on the paper, in paper pixels.
    func outline(pixelsPerMillimeter ppmm: Double) -> [CGPoint] {
        outlineMM.map { world(CGPoint(x: Double($0.x) * ppmm, y: Double($0.y) * ppmm)) }
    }

    /// A point on the paper in the sheet's own pixels, from its top-left corner.
    func surfacePoint(_ p: CGPoint, pixelsPerMillimeter ppmm: Double) -> CGPoint {
        let dx = Double(p.x - pose.center.x), dy = Double(p.y - pose.center.y)
        let c = cos(pose.angle), s = sin(pose.angle)
        let (w, h) = kind.sizeMM
        return CGPoint(x: (dx * c + dy * s) * mirror.x + w * ppmm / 2, y: (-dx * s + dy * c) * mirror.y + h * ppmm / 2)
    }

    /// A point in the sheet's own pixels, back on the paper.
    func paperPoint(fromSurface q: CGPoint, pixelsPerMillimeter ppmm: Double) -> CGPoint {
        let (w, h) = kind.sizeMM
        let u = (Double(q.x) - w * ppmm / 2) * mirror.x, v = (Double(q.y) - h * ppmm / 2) * mirror.y
        let c = cos(pose.angle), s = sin(pose.angle)
        return CGPoint(x: Double(pose.center.x) + u * c - v * s, y: Double(pose.center.y) + u * s + v * c)
    }

    /// A pencil sample as it lands on the sheet's own surface.
    func surfaceSample(_ sample: StrokeSample, pixelsPerMillimeter ppmm: Double) -> StrokeSample {
        var s = sample
        s.location = surfacePoint(sample.location, pixelsPerMillimeter: ppmm)
        s.azimuth -= pose.angle
        // The lean is mirrored too.
        if flippedX { s.azimuth = .pi - s.azimuth }
        if flippedY { s.azimuth = -s.azimuth }
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
        let x = Double(q.x) * mirror.x, y = Double(q.y) * mirror.y
        return CGPoint(x: Double(pose.center.x) + x * c - y * s,
                       y: Double(pose.center.y) + x * s + y * c)
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

    var isCarbonCopy: Bool {
        switch self {
        case .carbonCopy, .sheetCopy: true
        case .paper, .sheet: false
        }
    }
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
        stampRoutes(from: source).map { ($0.surface, $0.mask) }
    }

    /// As `stampTargets`, but where a carbon lies between the sheet and what
    /// takes the print, the print goes through it: a copy in the carbon's
    /// colour (the carbon nearest the target), as if inked from it.
    func stampRoutes(from source: Int) -> [(surface: SurfaceID, mask: StrokeMask, carbon: Int?)] {
        guard let i = sheets.firstIndex(where: { $0.id == source }) else { return [] }
        let outline = sheets[i].outline
        let below = sheets[..<i].enumerated().filter { !$0.element.isCarbon }
        var out: [(SurfaceID, StrokeMask, Int?)] = []
        /// Splits a route by the carbons lying between `level` and the source.
        func route(_ plain: SurfaceID, _ copy: SurfaceID, _ mask: StrokeMask, above level: Int) {
            let carbons = sheets.enumerated().filter { $0.offset > level && $0.offset < i && $0.element.isCarbon }
                .sorted { $0.offset < $1.offset }
            var clear = mask
            clear.outside += carbons.map(\.element.outline)
            out.append((plain, clear, nil))
            for (n, carbon) in carbons.enumerated() {
                var through = mask
                through.inside.append(carbon.element.outline)
                // The carbon nearest the target colours it.
                through.outside += carbons[..<n].map(\.element.outline)
                out.append((copy, through, carbon.element.id))
            }
        }
        for (j, sheet) in below {
            // Under the source, on this sheet, and not under a sheet between them.
            let between = below.filter { $0.offset > j }.map(\.element.outline)
            route(.sheet(sheet.id), .sheetCopy(sheet.id), StrokeMask(inside: [outline, sheet.outline], outside: between), above: j)
        }
        let onPaper = paper.map { [$0] } ?? []
        route(.paper, .carbonCopy, StrokeMask(inside: [outline] + onPaper, outside: below.map(\.element.outline)), above: -1)
        return out
    }

    /// The carbon a pencil pressing through copies with: the topmost one.
    var pressingCarbon: Int? { sheets.last(where: \.isCarbon)?.id }

    /// Every piece of carbon, topmost first: at each point the topmost one there gives the colour.
    var carbonsTopFirst: [Sheet] { sheets.filter(\.isCarbon).reversed() }

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
        } else if let top = sheets.lastIndex(where: \.isCarbon) {
            // Pressing through any piece of carbon copies onto what lies just under it.
            let carbons = sheets.indices.filter { sheets[$0].isCarbon }
            for i in sheets.indices where i < top && !sheets[i].isCarbon {
                let over = carbons.filter { $0 > i }
                let highest = over.max() ?? i
                let between = sheets.indices.filter { $0 > i && $0 < highest && !sheets[$0].isCarbon }.map { sheets[$0].outline }
                out.append((.sheetCopy(sheets[i].id),
                            StrokeMask(inside: [sheets[i].outline], outside: between, anyOf: over.map { sheets[$0].outline })))
            }
            let under = sheets.indices.filter { $0 < top && !sheets[$0].isCarbon }.map { sheets[$0].outline }
            out.append((.carbonCopy, StrokeMask(inside: onPaper, outside: under, anyOf: carbons.map { sheets[$0].outline })))
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
    /// Within at least one of these, when there are any: pieces of carbon side by side.
    var anyOf: [[CGPoint]] = []

    struct Shield: Sendable {
        var outline: [CGPoint]
        var openings: [[CGPoint]]

        func allows(_ p: CGPoint) -> Bool {
            !Polygon.contains(p, outline) || openings.contains { Polygon.contains(p, $0) }
        }
    }

    init(inside: [[CGPoint]], outside: [[CGPoint]], shields: [Shield] = [], anyOf: [[CGPoint]] = []) {
        self.inside = inside
        self.outside = outside
        self.shields = shields
        self.anyOf = anyOf
    }

    static let everywhere = StrokeMask(inside: [], outside: [])

    var isEverywhere: Bool { inside.isEmpty && outside.isEmpty && shields.isEmpty && anyOf.isEmpty }

    enum Coverage: Equatable { case none, all, part }

    func contains(_ p: CGPoint) -> Bool {
        inside.allSatisfy { Polygon.contains(p, $0) } && !outside.contains { Polygon.contains(p, $0) }
            && shields.allSatisfy { $0.allows(p) }
            && (anyOf.isEmpty || anyOf.contains { Polygon.contains(p, $0) })
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
        if !anyOf.isEmpty {
            let places = anyOf.map { Polygon.classify(rect, $0) }
            if places.allSatisfy({ $0 == .outside }) { return .none }
            if !places.contains(.inside) { all = false }
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
                   shields: shields.map { Shield(outline: $0.outline.map(transform), openings: $0.openings.map { $0.map(transform) }) },
                   anyOf: anyOf.map { $0.map(transform) })
    }
}

/// Small geometry on plain point lists.
enum Polygon {
    /// Twice the signed area: positive when the points run clockwise on screen.
    static func signedArea(_ polygon: [CGPoint]) -> Double {
        polygon.indices.reduce(0) { sum, i in
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            return sum + Double(a.x * b.y - b.x * a.y)
        }
    }

    /// Cuts a polygon in two along a path that runs in from outside and out
    /// again, crossing its rim exactly twice: a knife drawn across a sheet
    /// from edge to edge. Nil when the path doesn't part it.
    static func split(_ polygon: [CGPoint], along path: [CGPoint]) -> ([CGPoint], [CGPoint])? {
        guard polygon.count >= 3, path.count >= 2 else { return nil }
        // Every crossing: where along the path, which edge, how far along it.
        var crossings: [(s: Double, edge: Int, t: Double, point: CGPoint)] = []
        for j in 0..<(path.count - 1) {
            let p = path[j], q = path[j + 1]
            for i in polygon.indices {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                guard let (u, t) = intersect(p, q, a, b) else { continue }
                crossings.append((Double(j) + u, i, t,
                                  CGPoint(x: Double(p.x) + Double(q.x - p.x) * u, y: Double(p.y) + Double(q.y - p.y) * u)))
            }
        }
        guard crossings.count >= 2 else { return nil }
        crossings.sort { $0.s < $1.s }
        // The first stretch of the knife that runs through the sheet itself,
        // not along an edge an earlier cut left.
        func pointAt(_ s: Double) -> CGPoint {
            let j = min(Int(s), path.count - 2), u = s - Double(j)
            return CGPoint(x: Double(path[j].x) + Double(path[j + 1].x - path[j].x) * u,
                           y: Double(path[j].y) + Double(path[j + 1].y - path[j].y) * u)
        }
        guard let k = (0..<(crossings.count - 1)).first(where: { k in
            let mid = pointAt((crossings[k].s + crossings[k + 1].s) / 2)
            return contains(mid, polygon) && distance(mid, to: polygon) > 0.05
        }) else { return nil }
        let (enter, exit) = (crossings[k], crossings[k + 1])
        // The knife's path inside the sheet, between the two crossings.
        let inner = path.indices.filter { Double($0) > enter.s && Double($0) < exit.s }.map { path[$0] }
        /// Rim corners met walking forward from one crossing to the other.
        func rim(from: (edge: Int, t: Double), to: (edge: Int, t: Double)) -> [CGPoint] {
            if from.edge == to.edge, to.t > from.t { return [] }
            var out: [CGPoint] = []
            var i = (from.edge + 1) % polygon.count
            while true {
                out.append(polygon[i])
                if i == to.edge { break }
                i = (i + 1) % polygon.count
            }
            return out
        }
        let first = [enter.point] + rim(from: (enter.edge, enter.t), to: (exit.edge, exit.t)) + [exit.point] + inner.reversed()
        let second = [exit.point] + rim(from: (exit.edge, exit.t), to: (enter.edge, enter.t)) + [enter.point] + inner
        // A sliver is not a piece.
        guard abs(signedArea(first)) > 1, abs(signedArea(second)) > 1 else { return nil }
        return (first, second)
    }

    /// Cuts a sheet with a knife stroke, every way it parts it: across from
    /// edge to edge (again and again for a zigzag), or round in a closed loop
    /// that lifts out a piece. A stroke stopping within `reach` of an edge
    /// is taken to the edge. Nil when it parts nothing.
    static func cut(_ polygon: [CGPoint], along stroke: [CGPoint], reach: Double = 3) -> [[CGPoint]]? {
        var path = stroke.reduce(into: [CGPoint]()) { out, p in
            if out.last.map({ hypot(Double(p.x - $0.x), Double(p.y - $0.y)) > 1e-6 }) ?? true { out.append(p) }
        }
        guard path.count >= 2 else { return nil }
        let closed = hypot(Double(path[0].x - path[path.count - 1].x), Double(path[0].y - path[path.count - 1].y)) <= 4
        if !closed {
            func extend(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
                let dx = Double(to.x - from.x), dy = Double(to.y - from.y), l = hypot(dx, dy)
                return l > 0 ? CGPoint(x: Double(to.x) + dx / l * reach, y: Double(to.y) + dy / l * reach) : to
            }
            path.insert(extend(path[1], path[0]), at: 0)
            path.append(extend(path[path.count - 2], path[path.count - 1]))
        }
        var pieces = [polygon]
        var parted = false
        for _ in 0..<24 {
            guard let i = pieces.indices.first(where: { split(pieces[$0], along: path) != nil }),
                  let (a, b) = split(pieces[i], along: path) else { break }
            pieces.replaceSubrange(i...i, with: [a, b])
            parted = true
        }
        if parted { return pieces }
        // A closed loop wholly inside lifts out what it went round.
        guard closed, path.count >= 4, abs(signedArea(path)) / 2 > 20,
              path.allSatisfy({ contains($0, polygon) }) else { return nil }
        let loop = path
        // Keep the rest as one sheet with a hole: the rim, a hairline in to the
        // hole, round it, and back out the same way.
        var best = (rim: 0, hole: 0, d: Double.infinity)
        for (r, p) in polygon.enumerated() {
            for (h, q) in loop.enumerated() {
                let d = hypot(Double(p.x - q.x), Double(p.y - q.y))
                if d < best.d { best = (r, h, d) }
            }
        }
        // The hole runs the other way round from the rim, so it is a hole by any fill rule.
        var around = Array(loop[best.hole...]) + Array(loop[...best.hole])
        if (signedArea(loop) > 0) == (signedArea(polygon) > 0) { around.reverse() }
        let rest = Array(polygon[...best.rim]) + around + Array(polygon[best.rim...])
        return [rest, loop]
    }

    /// Where segment pq meets segment ab, as fractions along each.
    private static func intersect(_ p: CGPoint, _ q: CGPoint, _ a: CGPoint, _ b: CGPoint) -> (Double, Double)? {
        let r = (x: Double(q.x - p.x), y: Double(q.y - p.y)), s = (x: Double(b.x - a.x), y: Double(b.y - a.y))
        let denom = r.x * s.y - r.y * s.x
        guard abs(denom) > 1e-12 else { return nil }
        let ap = (x: Double(a.x - p.x), y: Double(a.y - p.y))
        let u = (ap.x * s.y - ap.y * s.x) / denom
        let t = (ap.x * r.y - ap.y * r.x) / denom
        guard u >= 0, u < 1, t >= 0, t < 1 else { return nil }
        return (u, t)
    }

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
        if corners.allSatisfy({ contains($0, polygon) }) {
            // A cut-out piece may be notched or holed: wholly inside only if no rim reaches into the rectangle.
            let reaches = polygon.indices.contains { i in
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                if Double(a.x) > Double(rect.minX), Double(a.x) < Double(rect.maxX), Double(a.y) > Double(rect.minY), Double(a.y) < Double(rect.maxY) {
                    return true
                }
                return (0..<4).contains { k in intersect(a, b, corners[k], corners[(k + 1) % 4]) != nil }
            }
            return reaches ? .part : .inside
        }
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

    /// The colour a sheet is printed in.
    enum Ink: Int, CaseIterable, Sendable {
        /// Drafting-film green.
        case green
        /// Manuscript-paper red.
        case red
        /// Non-photo blue, invisible to a copier.
        case blue
        /// Staff lines.
        case black
    }

    struct Line: Equatable, Sendable {
        var from: CGPoint
        var to: CGPoint
        var weight: Weight
        var ink: Ink = .green
        var dashed = false
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
        case .manuscript:
            return manuscript(width: w)
        case .genkou:
            return genkou(width: w, height: h)
        case .manga:
            return manga(width: w, height: h)
        case .squareBook:
            return squareBook(width: w, height: h)
        case .staff:
            return staff(width: w, height: h)
        case .fourLine:
            return fourLine(width: w, height: h)
        case .polar:
            let r = w / 2
            return stride(from: 0, to: 360, by: 15).map { degrees in
                let a = Double(degrees) * .pi / 180
                let weight: Weight = degrees % 90 == 0 ? .bold : degrees % 45 == 0 ? .medium : .fine
                return Line(from: CGPoint(x: r, y: r), to: CGPoint(x: r + r * cos(a), y: r + r * sin(a)), weight: weight)
            }
        }
    }

    /// The print as graphite on a sheet's own surface, for stamping it with
    /// the drawing: lines laid as a hard lead would, bolder lines darker.
    static func raster(_ pattern: GridPattern, pixelsPerMillimeter ppmm: Double, width: Int, height: Int) -> GraphiteRaster {
        var raster = GraphiteRaster(width: width, height: height)
        let widths = [0.12, 0.18, 0.28], densities: [Float] = [0.35, 0.5, 0.7]
        func dab(_ x: Double, _ y: Double, _ weight: Weight) {
            let r = max(widths[weight.rawValue] / 2 * ppmm, 0.6)
            let area = PixelRect(minX: Int(x - r - 1), minY: Int(y - r - 1), maxX: Int(x + r + 2), maxY: Int(y + r + 2)).intersection(raster.bounds)
            guard !area.isEmpty else { return }
            for coord in raster.tileCoords(overlapping: area) {
                let rect = raster.rect(of: coord).intersection(area), ts = GraphiteRaster.tileSize
                raster.withMutableTile(coord) { b in
                    for py in rect.minY..<rect.maxY {
                        for px in rect.minX..<rect.maxX {
                            let d = hypot(Double(px) + 0.5 - x, Double(py) + 0.5 - y)
                            let v = densities[weight.rawValue] * Float(min(max(r + 0.5 - d, 0), 1))
                            let i = (py - coord.y * ts) * ts + (px - coord.x * ts)
                            if v > b[i] { b[i] = v }
                        }
                    }
                }
            }
        }
        for line in lines(pattern) {
            let ax = Double(line.from.x) * ppmm, ay = Double(line.from.y) * ppmm
            let bx = Double(line.to.x) * ppmm, by = Double(line.to.y) * ppmm
            let length = hypot(bx - ax, by - ay), steps = max(Int(length / 0.6), 1)
            for k in 0...steps {
                let t = Double(k) / Double(steps)
                // Dashes of 0.8 mm, as printed.
                if line.dashed, Int(t * length / (0.8 * ppmm)) % 2 == 1 { continue }
                dab(ax + (bx - ax) * t, ay + (by - ay) * t, line.weight)
            }
        }
        let c = (x: Double(width) / 2, y: Double(height) / 2)
        for ring in rings(pattern) {
            let r = ring.radius * ppmm, steps = max(Int(2 * .pi * r / 0.6), 8)
            for k in 0..<steps {
                let a = Double(k) / Double(steps) * 2 * .pi
                dab(c.x + r * cos(a), c.y + r * sin(a), ring.weight)
            }
        }
        return raster
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

    private static func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ weight: Weight, _ ink: Ink,
                            dashed: Bool = false) -> [Line] {
        let a = CGPoint(x: x0, y: y0), b = CGPoint(x: x1, y: y0), c = CGPoint(x: x1, y: y1), d = CGPoint(x: x0, y: y1)
        return [(a, b), (b, c), (c, d), (d, a)].map { Line(from: $0.0, to: $0.1, weight: weight, ink: ink, dashed: dashed) }
    }

    /// 20 squares of 8 mm a row, ten rows, a 3 mm strip between rows, in a heavy frame.
    private static func manuscript(width: Double) -> [Line] {
        let cell = 8.0, gap = 3.0, margin = 10.0, columns = 20, rows = 10
        let right = margin + Double(columns) * cell
        var out: [Line] = []
        for r in 0..<rows {
            let top = margin + Double(r) * (cell + gap), bottom = top + cell
            out.append(Line(from: CGPoint(x: margin, y: top), to: CGPoint(x: right, y: top), weight: .medium, ink: .red))
            out.append(Line(from: CGPoint(x: margin, y: bottom), to: CGPoint(x: right, y: bottom), weight: .medium, ink: .red))
            for c in 1..<columns {
                let x = margin + Double(c) * cell
                out.append(Line(from: CGPoint(x: x, y: top), to: CGPoint(x: x, y: bottom), weight: .fine, ink: .red))
            }
        }
        let bottom = margin + Double(rows) * cell + Double(rows - 1) * gap
        return out + box(margin, margin, right, bottom, .bold, .red)
    }

    /// Ten columns of 20 squares each side of the fold strip, a 2 mm gap between columns.
    private static func genkou(width: Double, height: Double) -> [Line] {
        let cell = 8.0, gap = 2.0, fold = 10.0, margin = 10.0, rows = 20
        let top = margin, bottom = margin + Double(rows) * cell
        var out: [Line] = []
        var x = margin
        for column in 0..<20 {
            if column == 10 { x += fold - gap }
            let left = x, right = x + cell
            out.append(Line(from: CGPoint(x: left, y: top), to: CGPoint(x: left, y: bottom), weight: .medium, ink: .red))
            out.append(Line(from: CGPoint(x: right, y: top), to: CGPoint(x: right, y: bottom), weight: .medium, ink: .red))
            for r in 1..<rows {
                let y = top + Double(r) * cell
                out.append(Line(from: CGPoint(x: left, y: y), to: CGPoint(x: right, y: y), weight: .fine, ink: .red))
            }
            x = right + gap
        }
        // The fold strip's marks, top and bottom.
        let mid = width / 2
        for y in [top + 4, bottom - 4] {
            out.append(Line(from: CGPoint(x: mid - 2.5, y: y), to: CGPoint(x: mid + 2.5, y: y), weight: .medium, ink: .red))
        }
        return out + box(margin - 2, top - 2, width - margin + 2, bottom + 2, .bold, .red)
    }

    /// B4 comic paper finished at B5: the trim (182×257), the bleed 3 mm past
    /// it, the inner frame (150×220), and crop marks at the corners and middles.
    private static func manga(width: Double, height: Double) -> [Line] {
        let cx = width / 2, cy = height / 2
        func centred(_ w: Double, _ h: Double, _ weight: Weight, dashed: Bool = false) -> [Line] {
            box(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, weight, .blue, dashed: dashed)
        }
        var out = centred(182, 257, .medium) + centred(188, 263, .fine) + centred(150, 220, .medium)
        // Crop marks: two strokes at each corner of the trim, out beyond the bleed.
        let (tx, ty) = (182.0 / 2, 257.0 / 2), reach = 12.0, off = 3.0
        for (sx, sy) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
            for (dx, dy) in [(tx, ty), (tx + off, ty + off)] {
                let corner = CGPoint(x: cx + sx * dx, y: cy + sy * dy)
                out.append(Line(from: CGPoint(x: cx + sx * (tx + off), y: corner.y),
                                to: CGPoint(x: cx + sx * (tx + off + reach), y: corner.y), weight: .fine, ink: .blue))
                out.append(Line(from: CGPoint(x: corner.x, y: cy + sy * (ty + off)),
                                to: CGPoint(x: corner.x, y: cy + sy * (ty + off + reach)), weight: .fine, ink: .blue))
            }
        }
        // Centre marks on each side.
        for s in [-1.0, 1.0] {
            out.append(Line(from: CGPoint(x: cx, y: cy + s * (ty + off)), to: CGPoint(x: cx, y: cy + s * (ty + off + reach)), weight: .fine, ink: .blue))
            out.append(Line(from: CGPoint(x: cx + s * (tx + off), y: cy), to: CGPoint(x: cx + s * (tx + off + reach), y: cy), weight: .fine, ink: .blue))
            out.append(Line(from: CGPoint(x: cx - 5, y: cy + s * (ty + off + reach / 2)), to: CGPoint(x: cx + 5, y: cy + s * (ty + off + reach / 2)), weight: .fine, ink: .blue))
            out.append(Line(from: CGPoint(x: cx + s * (tx + off + reach / 2), y: cy - 5), to: CGPoint(x: cx + s * (tx + off + reach / 2), y: cy + 5), weight: .fine, ink: .blue))
        }
        return out
    }

    /// 14 mm squares, each with a dotted cross through its middle.
    private static func squareBook(width: Double, height: Double) -> [Line] {
        let cell = 14.0, margin = 10.0
        let columns = Int(((width - 2 * margin) / cell).rounded(.down)), rows = Int(((height - 2 * margin) / cell).rounded(.down))
        let right = margin + Double(columns) * cell, bottom = margin + Double(rows) * cell
        var out: [Line] = []
        for c in 0...columns {
            let x = margin + Double(c) * cell
            out.append(Line(from: CGPoint(x: x, y: margin), to: CGPoint(x: x, y: bottom), weight: c == 0 || c == columns ? .bold : .medium, ink: .green))
            if c < columns {
                out.append(Line(from: CGPoint(x: x + cell / 2, y: margin), to: CGPoint(x: x + cell / 2, y: bottom), weight: .fine, ink: .green, dashed: true))
            }
        }
        for r in 0...rows {
            let y = margin + Double(r) * cell
            out.append(Line(from: CGPoint(x: margin, y: y), to: CGPoint(x: right, y: y), weight: r == 0 || r == rows ? .bold : .medium, ink: .green))
            if r < rows {
                out.append(Line(from: CGPoint(x: margin, y: y + cell / 2), to: CGPoint(x: right, y: y + cell / 2), weight: .fine, ink: .green, dashed: true))
            }
        }
        return out
    }

    /// Staves of five lines 2 mm apart, one every 16 mm down an A4 sheet.
    private static func staff(width: Double, height: Double) -> [Line] {
        let margin = 12.0, space = 2.0, pitch = 16.0
        var out: [Line] = []
        var top = 20.0
        while top + 4 * space <= height - 14 {
            for k in 0..<5 {
                let y = top + Double(k) * space
                out.append(Line(from: CGPoint(x: margin, y: y), to: CGPoint(x: width - margin, y: y), weight: .medium, ink: .black))
            }
            for x in [margin, width - margin] {
                out.append(Line(from: CGPoint(x: x, y: top), to: CGPoint(x: x, y: top + 4 * space), weight: .medium, ink: .black))
            }
            top += pitch
        }
        return out
    }

    /// Sets of four lines 3 mm apart, 15 mm a set: blue, with the third (the base line) red.
    private static func fourLine(width: Double, height: Double) -> [Line] {
        let margin = 12.0, space = 3.0, pitch = 15.0
        var out: [Line] = []
        var top = 18.0
        while top + 3 * space <= height - 12 {
            for k in 0..<4 {
                let y = top + Double(k) * space
                out.append(Line(from: CGPoint(x: margin, y: y), to: CGPoint(x: width - margin, y: y),
                                weight: k == 2 ? .medium : .fine, ink: k == 2 ? .red : .blue, dashed: k == 1))
            }
            top += pitch
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
