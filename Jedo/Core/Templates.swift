import CoreGraphics
import Foundation

/// One shape cut through a template, in millimetres about the template's centre.
struct TemplateCut: Sendable {
    /// The cut's rim, closed.
    var outline: [CGPoint]
    var center: CGPoint
    /// Its marked size, printed beside it.
    var label: String
    /// Half its width and height, for placing the label and the axis marks.
    var halfSize: CGSize
    /// Whether short marks on its axes help line it up with centre lines.
    var axisMarks: Bool
    /// Where its size is printed, if not just above it.
    var labelAt: CGPoint? = nil
}

/// The shape templates (형판) other than the circle template: thin tinted
/// sheets with shapes cut through them, each cut a little larger than its
/// marked size so a lead run round inside it draws that size.
enum ShapeTemplate {
    /// How a cut is drawn: its rim about its own centre, for a marked size.
    private struct Item {
        var size: Double
        var label: String
        var rim: (Double) -> [CGPoint]
        var halfSize: (Double) -> CGSize
        var axisMarks: Bool
    }

    static let marginMM = 7.0
    static let gapMM = 4.0
    /// Room above each cut for its size.
    static let labelMM = 4.0
    /// Each cut is this much larger all round than its marked size.
    static let leadAllowanceMM = 0.25

    /// Isometric ellipses: minor axis 0.577 of the major (a circle seen at 35°16′).
    static let isometricRatio = 1 / 3.0.squareRoot()

    static func name(_ kind: ToolKind) -> String {
        switch kind {
        case .ellipseTemplate: "타원"
        case .squareTemplate: "사각·삼각"
        case .hexTemplate: "육각·팔각"
        case .arcTemplate: "원주 1/4"
        case .letteringGuide: "레터링"
        case .erasingShield: "지움판"
        case .brailleSlate: "점판"
        case .morsePlate: "모스 부호판"
        default: "원"
        }
    }

    private static func rows(_ kind: ToolKind) -> [[Item]] {
        let a = leadAllowanceMM
        func ellipse(_ major: Double) -> Item {
            Item(size: major, label: "\(Int(major))", rim: { m in
                (0..<96).map { k in
                    let t = Double(k) / 96 * 2 * .pi
                    return CGPoint(x: cos(t) * (m / 2 + a), y: sin(t) * (m / 2 * isometricRatio + a))
                }
            }, halfSize: { m in CGSize(width: m / 2 + a, height: m / 2 * isometricRatio + a) }, axisMarks: true)
        }
        func polygon(_ size: Double, sides: Int, label: String, turned: Double, acrossFlats: Bool) -> Item {
            // `size` is the side for squares and triangles, the width across flats for the rest.
            let circumradius: Double
            if acrossFlats {
                circumradius = size / 2 / cos(.pi / Double(sides))
            } else {
                circumradius = size / (2 * sin(.pi / Double(sides)))
            }
            let r = circumradius + a / cos(.pi / Double(sides))
            let corners = (0..<sides).map { k -> CGPoint in
                let t = turned + Double(k) / Double(sides) * 2 * .pi
                return CGPoint(x: cos(t) * r, y: sin(t) * r)
            }
            let ys = corners.map(\.y), xs = corners.map(\.x)
            // Centre the shape on its own bounding box, so triangles sit level in their row.
            let dy = ((ys.max() ?? 0) + (ys.min() ?? 0)) / 2
            let centred = corners.map { CGPoint(x: $0.x, y: $0.y - dy) }
            let half = CGSize(width: ((xs.max() ?? 0) - (xs.min() ?? 0)) / 2, height: ((ys.max() ?? 0) - (ys.min() ?? 0)) / 2)
            return Item(size: size, label: label, rim: { _ in centred }, halfSize: { _ in half }, axisMarks: false)
        }
        switch kind {
        case .ellipseTemplate:
            return [[8, 10, 12, 14, 16, 18, 20].map(ellipse), [24, 28, 32, 36].map(ellipse)]
        case .squareTemplate:
            return [
                [4, 6, 8, 10, 12, 15, 18, 20].map { polygon($0, sides: 4, label: "\(Int($0))", turned: .pi / 4, acrossFlats: false) },
                [6, 8, 10, 14, 18, 22, 26].map { polygon($0, sides: 3, label: "\(Int($0))", turned: -.pi / 2, acrossFlats: false) },
            ]
        case .hexTemplate:
            return [
                [5, 7, 9, 11, 13, 16, 19, 22].map { polygon($0, sides: 6, label: "\(Int($0))", turned: 0, acrossFlats: true) },
                [8, 10, 13, 16, 20, 24].map { polygon($0, sides: 8, label: "\(Int($0))", turned: .pi / 8, acrossFlats: true) },
            ]
        default:
            return []
        }
    }

    /// The template's cuts and its overall size, laid out row by row.
    static let layouts: [ToolKind: (size: CGSize, cuts: [TemplateCut])] = {
        var out: [ToolKind: (size: CGSize, cuts: [TemplateCut])] = [:]
        for kind in [ToolKind.ellipseTemplate, .squareTemplate, .hexTemplate] {
            let rows = rows(kind)
            let rowWidths = rows.map { row in row.reduce(0) { $0 + 2 * Double($1.halfSize($1.size).width) } + gapMM * Double(row.count - 1) }
            let rowHeights = rows.map { row in row.map { 2 * Double($0.halfSize($0.size).height) }.max() ?? 0 }
            let width = (rowWidths.max() ?? 0) + 2 * marginMM
            let height = rowHeights.reduce(0) { $0 + $1 + labelMM } + gapMM * Double(rows.count - 1) + 2 * marginMM
            var cuts: [TemplateCut] = []
            var y = -height / 2 + marginMM
            for (row, items) in rows.enumerated() {
                y += labelMM
                let centreY = y + rowHeights[row] / 2
                var x = -rowWidths[row] / 2
                for item in items {
                    let half = item.halfSize(item.size)
                    let cx = x + Double(half.width)
                    let rim = item.rim(item.size).map { CGPoint(x: Double($0.x) + cx, y: Double($0.y) + centreY) }
                    cuts.append(TemplateCut(outline: rim, center: CGPoint(x: cx, y: centreY), label: item.label,
                                            halfSize: half, axisMarks: item.axisMarks))
                    x += 2 * Double(half.width) + gapMM
                }
                y += rowHeights[row] + gapMM
            }
            out[kind] = (CGSize(width: width, height: height), cuts)
        }
        out[.arcTemplate] = arcLayout()
        out[.letteringGuide] = letteringLayout()
        out[.erasingShield] = shieldLayout()
        out[.brailleSlate] = brailleLayout()
        out[.morsePlate] = morseLayout()
        return out
    }()

    // MARK: Quarter-circle radius template (원주 형판)

    /// A square plate with quarter-circle slots round one corner, for arcs
    /// too big for a circle template. The pencil runs in a slot; its marked
    /// radius is the slot's middle.
    static let arcPlateMM = 250.0
    /// The slots' common centre, in from the plate's lower left corner.
    static let arcCentreInsetMM = 12.0
    static let arcRadiiMM: [Double] = [25, 40, 55, 70, 85, 100, 115, 130, 145, 160, 175, 190, 205, 220]
    static let arcSlotWidthMM = 2.5
    /// Each slot stops short of the plate's edges by this angle, so the plate holds together.
    static let arcEndDegrees = 3.0

    static var arcCentre: CGPoint {
        CGPoint(x: -arcPlateMM / 2 + arcCentreInsetMM, y: arcPlateMM / 2 - arcCentreInsetMM)
    }

    private static func arcLayout() -> (size: CGSize, cuts: [TemplateCut]) {
        let c = arcCentre, w = arcSlotWidthMM / 2
        // Up the left side (−90°, pointing up) round to the bottom (0°, pointing right).
        let from = (-90 + arcEndDegrees) * .pi / 180, to = -arcEndDegrees * .pi / 180
        func at(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: Double(c.x) + cos(a) * r, y: Double(c.y) + sin(a) * r) }
        let cuts = arcRadiiMM.map { r -> TemplateCut in
            let steps = max(Int((to - from) * r / 1.0), 24)
            var rim: [CGPoint] = (0...steps).map { at(r + w, from + (to - from) * Double($0) / Double(steps)) }
            // Round end at `to`, from the outer rim to the inner.
            rim += (1..<12).map { k in
                let end = at(r, to), a = to + Double(k) / 12 * .pi
                return CGPoint(x: Double(end.x) + cos(a) * w, y: Double(end.y) + sin(a) * w)
            }
            rim += (0...steps).map { at(r - w, to - (to - from) * Double($0) / Double(steps)) }
            rim += (1..<12).map { k in
                let end = at(r, from), a = from + .pi + Double(k) / 12 * .pi
                return CGPoint(x: Double(end.x) + cos(a) * w, y: Double(end.y) + sin(a) * w)
            }
            return TemplateCut(outline: rim, center: c, label: "R\(Int(r))", halfSize: CGSize(width: r + w, height: r + w),
                               axisMarks: false, labelAt: at(r + 6.5, -.pi / 4))
        }
        return (CGSize(width: arcPlateMM, height: arcPlateMM), cuts)
    }

    // MARK: Lettering guide (레터링 가이드)

    /// Letter heights h of KS A ISO 3098, in millimetres.
    static let letterHeightsMM: [Double] = [2.5, 3.5, 5, 7, 10]
    /// Lower-case letters stand 7/10 of h. Only the larger heights get a
    /// slot for them: on the small ones it would leave too thin a web.
    static let lowerCaseRatio = 0.7
    static let lowerCaseFromMM = 7.0
    /// Slots wide enough for a 0.5 mm lead: run along either side, the line lands on the slot's middle.
    static let letteringSlotMM = 0.6
    static let letteringPlate = CGSize(width: 160, height: 70)
    /// The slant of inclined lettering: 15° from upright.
    static let letteringSlantDegrees = 75.0

    /// A clear plate, laid on the parallel rule, with a set of slots for each
    /// letter height: the base line, the cap line and, for larger letters,
    /// the lower-case line. Run the pencil along each slot, slide the plate
    /// down the rule, and repeat. Two short slots on the right draw upright
    /// and 75° slant guides.
    private static func letteringLayout() -> (size: CGSize, cuts: [TemplateCut]) {
        let w = letteringSlotMM / 2
        let plate = letteringPlate
        let from = -plate.width / 2 + 22, to = plate.width / 2 - 34
        func slot(_ a: CGPoint, _ b: CGPoint, label: String = "", labelAt: CGPoint? = nil) -> TemplateCut {
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let angle = atan2(dy, dx)
            var rim: [CGPoint] = []
            for (end, start) in [(b, angle - .pi / 2), (a, angle + .pi / 2)] {
                for k in 0...12 {
                    let t = start + Double(k) / 12 * .pi
                    rim.append(CGPoint(x: Double(end.x) + cos(t) * w, y: Double(end.y) + sin(t) * w))
                }
            }
            return TemplateCut(outline: rim, center: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), label: label,
                               halfSize: CGSize(width: abs(dx) / 2 + w, height: abs(dy) / 2 + w), axisMarks: false,
                               labelAt: labelAt ?? (label.isEmpty ? nil : a))
        }
        var cuts: [TemplateCut] = []
        let gap = 6.0
        let total = letterHeightsMM.reduce(0, +) + gap * Double(letterHeightsMM.count - 1)
        var top = -total / 2
        for h in letterHeightsMM {
            let cap = top, base = top + h
            let label = h == h.rounded() ? "\(Int(h))" : "\(h)"
            cuts.append(slot(CGPoint(x: from, y: base), CGPoint(x: to, y: base),
                             label: label, labelAt: CGPoint(x: from - 9, y: (cap + base) / 2)))
            cuts.append(slot(CGPoint(x: from, y: cap), CGPoint(x: to, y: cap)))
            if h >= lowerCaseFromMM {
                let lower = base - h * lowerCaseRatio
                cuts.append(slot(CGPoint(x: from + 6, y: lower), CGPoint(x: to, y: lower)))
            }
            top = base + gap
        }
        // Upright and slanted stems, for lining up letters.
        let span = total / 2
        cuts.append(slot(CGPoint(x: to + 12, y: -span), CGPoint(x: to + 12, y: span), label: "90°",
                         labelAt: CGPoint(x: to + 12, y: span + 4.5)))
        let lean = tan((90 - letteringSlantDegrees) * .pi / 180) * span
        cuts.append(slot(CGPoint(x: to + 24 - lean, y: span), CGPoint(x: to + 24 + lean, y: -span), label: "75°",
                         labelAt: CGPoint(x: to + 24 - lean, y: span + 4.5)))
        return (plate, cuts)
    }

    // MARK: Erasing shield (지움판)

    static let shieldPlate = CGSize(width: 100, height: 62)

    /// A stainless plate as sold for drafting: long slots of several widths
    /// for lines, round holes and squares for points and corners. Erase
    /// through an opening and only what shows through it goes.
    private static func shieldLayout() -> (size: CGSize, cuts: [TemplateCut]) {
        func slot(_ a: CGPoint, _ b: CGPoint, width: Double) -> TemplateCut {
            let w = width / 2, dx = Double(b.x - a.x), dy = Double(b.y - a.y), angle = atan2(dy, dx)
            var rim: [CGPoint] = []
            for (end, start) in [(b, angle - .pi / 2), (a, angle + .pi / 2)] {
                for k in 0...8 {
                    let t = start + Double(k) / 8 * .pi
                    rim.append(CGPoint(x: Double(end.x) + cos(t) * w, y: Double(end.y) + sin(t) * w))
                }
            }
            return TemplateCut(outline: rim, center: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), label: "",
                               halfSize: CGSize(width: abs(dx) / 2 + w, height: abs(dy) / 2 + w), axisMarks: false)
        }
        func hole(_ c: CGPoint, diameter: Double) -> TemplateCut {
            let r = diameter / 2
            let rim = (0..<24).map { k -> CGPoint in
                let t = Double(k) / 24 * 2 * .pi
                return CGPoint(x: Double(c.x) + cos(t) * r, y: Double(c.y) + sin(t) * r)
            }
            return TemplateCut(outline: rim, center: c, label: "", halfSize: CGSize(width: r, height: r), axisMarks: false)
        }
        func square(_ c: CGPoint, side: Double) -> TemplateCut {
            let h = side / 2
            return TemplateCut(outline: [CGPoint(x: c.x - h, y: c.y - h), CGPoint(x: c.x + h, y: c.y - h),
                                         CGPoint(x: c.x + h, y: c.y + h), CGPoint(x: c.x - h, y: c.y + h)],
                               center: c, label: "", halfSize: CGSize(width: h, height: h), axisMarks: false)
        }
        var cuts: [TemplateCut] = []
        // Long slots, narrow to wide.
        for (i, width) in [0.8, 1.2, 2.0, 3.0].enumerated() {
            let y = -22.0 + Double(i) * 8
            cuts.append(slot(CGPoint(x: -42, y: y), CGPoint(x: 2, y: y), width: width))
        }
        // Upright slots.
        for (i, width) in [1.0, 2.0].enumerated() {
            let x = 10.0 + Double(i) * 7
            cuts.append(slot(CGPoint(x: x, y: -24), CGPoint(x: x, y: 4), width: width))
        }
        // A slanted one, for diagonals.
        cuts.append(slot(CGPoint(x: 28, y: 4), CGPoint(x: 42, y: -24), width: 1.5))
        // Round holes and squares along the bottom.
        for (i, d) in [2.0, 3.0, 4.5, 6.0].enumerated() {
            cuts.append(hole(CGPoint(x: -38 + Double(i) * 11, y: 16), diameter: d))
        }
        cuts.append(square(CGPoint(x: 10, y: 16), side: 3))
        cuts.append(square(CGPoint(x: 21, y: 16), side: 5))
        cuts.append(slot(CGPoint(x: 30, y: 16), CGPoint(x: 42, y: 16), width: 6))
        return (shieldPlate, cuts)
    }

    // MARK: Braille slate (점판)

    /// Braille's own measures: dots 2.5 mm apart in a cell, cells 6.2 mm, lines 10 mm.
    static let brailleDotMM = 2.5
    static let brailleCellMM = 6.2
    static let brailleLineMM = 10.0
    static let brailleCells = 18
    static let brailleLines = 4

    private static func round(_ c: CGPoint, diameter: Double, segments: Int = 12) -> TemplateCut {
        let r = diameter / 2
        let rim = (0..<segments).map { k -> CGPoint in
            let t = Double(k) / Double(segments) * 2 * .pi
            return CGPoint(x: Double(c.x) + cos(t) * r, y: Double(c.y) + sin(t) * r)
        }
        return TemplateCut(outline: rim, center: c, label: "", halfSize: CGSize(width: r, height: r), axisMarks: false)
    }

    /// Four lines of 18 cells, each cell six holes in two columns of three,
    /// numbered 1–3 down the left and 4–6 down the right.
    private static func brailleLayout() -> (size: CGSize, cuts: [TemplateCut]) {
        let side = 9.0, top = 12.0, bottom = 7.0
        let width = Double(brailleCells - 1) * brailleCellMM + brailleDotMM + 2 * side
        let height = Double(brailleLines - 1) * brailleLineMM + 2 * brailleDotMM + top + bottom
        var cuts: [TemplateCut] = []
        for line in 0..<brailleLines {
            for cell in 0..<brailleCells {
                let x0 = -width / 2 + side + Double(cell) * brailleCellMM
                let y0 = -height / 2 + top + Double(line) * brailleLineMM
                for column in 0..<2 {
                    for row in 0..<3 {
                        cuts.append(round(CGPoint(x: x0 + Double(column) * brailleDotMM, y: y0 + Double(row) * brailleDotMM), diameter: 1.6))
                    }
                }
            }
        }
        return (CGSize(width: width, height: height), cuts)
    }

    // MARK: Morse plate (모스 부호판)

    static let morsePlate = CGSize(width: 172, height: 86)

    /// International Morse, then Korean (the 1960s table still taught to radio amateurs).
    static let morseTable: [(String, String)] = [
        ("A", "·−"), ("B", "−···"), ("C", "−·−·"), ("D", "−··"), ("E", "·"), ("F", "··−·"), ("G", "−−·"), ("H", "····"),
        ("I", "··"), ("J", "·−−−"), ("K", "−·−"), ("L", "·−··"), ("M", "−−"), ("N", "−·"), ("O", "−−−"), ("P", "·−−·"),
        ("Q", "−−·−"), ("R", "·−·"), ("S", "···"), ("T", "−"), ("U", "··−"), ("V", "···−"), ("W", "·−−"), ("X", "−··−"),
        ("Y", "−·−−"), ("Z", "−−··"), ("1", "·−−−−"), ("2", "··−−−"), ("3", "···−−"), ("4", "····−"), ("5", "·····"),
        ("6", "−····"), ("7", "−−···"), ("8", "−−−··"), ("9", "−−−−·"), ("0", "−−−−−"),
        ("ㄱ", "·−··"), ("ㄴ", "··−·"), ("ㄷ", "−···"), ("ㄹ", "···−"), ("ㅁ", "−−"), ("ㅂ", "·−−"), ("ㅅ", "−−·"),
        ("ㅇ", "−·−"), ("ㅈ", "·−−·"), ("ㅊ", "−·−·"), ("ㅋ", "−··−"), ("ㅌ", "−−··"), ("ㅍ", "−−−"), ("ㅎ", "·−−−"),
        ("ㅏ", "·"), ("ㅑ", "··"), ("ㅓ", "−"), ("ㅕ", "···"), ("ㅗ", "·−"), ("ㅛ", "−·"), ("ㅜ", "····"), ("ㅠ", "·−·"),
        ("ㅡ", "−··"), ("ㅣ", "··−"), ("ㅐ", "−−·−"), ("ㅔ", "−·−−"),
    ]

    /// Where the engraved table sits on the plate, in millimetres about its centre.
    static let morseTableRect = CGRect(x: -80, y: -38, width: 160, height: 50)

    /// Two rows of stencil along the bottom: a dot hole, a dash slot, and so on.
    private static func morseLayout() -> (size: CGSize, cuts: [TemplateCut]) {
        let plate = morsePlate, dot = 2.4, dash = 7.0, gap = 3.2
        var cuts: [TemplateCut] = []
        for (r, y) in [22.0, 32.0].enumerated() {
            var x = -plate.width / 2 + 12 + Double(r) * (dot + gap)
            while x + dash < plate.width / 2 - 10 {
                cuts.append(round(CGPoint(x: x + dot / 2, y: y), diameter: dot, segments: 16))
                x += dot + gap
                let a = CGPoint(x: x + dot / 2, y: y), b = CGPoint(x: x + dash - dot / 2, y: y)
                var rim: [CGPoint] = []
                for (end, start) in [(b, -Double.pi / 2), (a, Double.pi / 2)] {
                    for k in 0...8 {
                        let t = start + Double(k) / 8 * .pi
                        rim.append(CGPoint(x: Double(end.x) + cos(t) * dot / 2, y: Double(end.y) + sin(t) * dot / 2))
                    }
                }
                cuts.append(TemplateCut(outline: rim, center: CGPoint(x: x + dash / 2, y: y), label: "",
                                        halfSize: CGSize(width: dash / 2, height: dot / 2), axisMarks: false))
                x += dash + gap
            }
        }
        return (plate, cuts)
    }

    static func size(_ kind: ToolKind) -> CGSize { layouts[kind]?.size ?? .zero }
    static func cuts(_ kind: ToolKind) -> [TemplateCut] { layouts[kind]?.cuts ?? [] }
}
