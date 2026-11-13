import CoreGraphics
import Foundation
import Testing
@testable import Jedo

private let ppmm = 10.0

private func square(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> [CGPoint] {
    [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
}

struct StrokeMaskTests {
    @Test func rectanglesAreWhollyInWhollyOutOrAcrossTheEdge() {
        let sheet = square(100, 100, 300, 300)
        #expect(Polygon.classify(PixelRect(minX: 150, minY: 150, maxX: 160, maxY: 160), sheet) == .inside)
        #expect(Polygon.classify(PixelRect(minX: 10, minY: 10, maxX: 20, maxY: 20), sheet) == .outside)
        #expect(Polygon.classify(PixelRect(minX: 95, minY: 150, maxX: 105, maxY: 160), sheet) == .part)
        // Beside a corner of a turned sheet, inside its bounding box but clear of it.
        let diamond = [CGPoint(x: 200, y: 100), CGPoint(x: 300, y: 200), CGPoint(x: 200, y: 300), CGPoint(x: 100, y: 200)]
        #expect(Polygon.classify(PixelRect(minX: 105, minY: 105, maxX: 115, maxY: 115), diamond) == .outside)
    }

    @Test func insideAndOutsideCombine() {
        let mask = StrokeMask(inside: [square(0, 0, 100, 100)], outside: [square(50, 0, 100, 100)])
        #expect(mask.contains(CGPoint(x: 25, y: 50)))
        #expect(!mask.contains(CGPoint(x: 75, y: 50)), "under a sheet lying above")
        #expect(!mask.contains(CGPoint(x: 150, y: 50)), "off the sheet")
        #expect(mask.coverage(PixelRect(minX: 10, minY: 10, maxX: 20, maxY: 20)) == .all)
        #expect(mask.coverage(PixelRect(minX: 60, minY: 10, maxX: 70, maxY: 20)) == .none)
        #expect(mask.coverage(PixelRect(minX: 45, minY: 10, maxX: 55, maxY: 20)) == .part)
        #expect(StrokeMask.everywhere.coverage(PixelRect(minX: 0, minY: 0, maxX: 5, maxY: 5)) == .all)
    }

    @Test func aLineStopsCleanlyAtTheMasksEdge() {
        let sheet = DraftingSheet(width: 400, height: 200, pixelsPerMillimeter: ppmm, paper: PaperTexture(size: 64, seed: 2))
        sheet.beginStroke(grade: .b4, mask: StrokeMask(inside: [square(0, 0, 200, 200)], outside: []))
        sheet.extendStroke(with: (0...50).map { StrokeSample(location: CGPoint(x: 20 + Double($0) * 7, y: 100), pressure: 0.8) },
                           predicted: [])
        #expect(sheet.endStroke())
        var inside: Float = 0, outside: Float = 0
        for y in 90..<110 {
            for x in 20..<190 { inside += sheet.graphite.value(x: x, y: y) }
            for x in 200..<380 { outside += sheet.graphite.value(x: x, y: y) }
        }
        #expect(inside > 0)
        #expect(outside == 0)
    }

    @Test func aStrokeWhollyMaskedAwayLeavesNothingToUndo() {
        let sheet = DraftingSheet(width: 400, height: 200, pixelsPerMillimeter: ppmm)
        sheet.beginStroke(grade: .hb, mask: StrokeMask(inside: [square(300, 0, 400, 200)], outside: []))
        sheet.extendStroke(with: (0...10).map { StrokeSample(location: CGPoint(x: 20 + Double($0) * 5, y: 100)) }, predicted: [])
        #expect(!sheet.endStroke())
        #expect(!sheet.canUndo)
    }

    @Test func theEraserIsMaskedToo() {
        let sheet = DraftingSheet(width: 400, height: 200, pixelsPerMillimeter: ppmm)
        let line = (0...50).map { StrokeSample(location: CGPoint(x: 20 + Double($0) * 7, y: 100), pressure: 0.8) }
        sheet.beginStroke(grade: .b4)
        sheet.extendStroke(with: line, predicted: [])
        sheet.endStroke()
        func ink(_ xs: Range<Int>) -> Float {
            var total: Float = 0
            for y in 90..<110 { for x in xs { total += sheet.graphite.value(x: x, y: y) } }
            return total
        }
        let right = ink(250..<350)
        sheet.beginErasing(mask: StrokeMask(inside: [], outside: [square(200, 0, 400, 200)]))
        var tracker = RubTracker(pixelsPerMillimeter: ppmm)
        let rub = (0..<6).flatMap { i in
            (i % 2 == 0 ? Array(stride(from: 40.0, through: 360, by: 4)) : Array(stride(from: 360.0, through: 40, by: -4)))
                .map { StrokeSample(location: CGPoint(x: $0, y: 100), pressure: 0.8) }
        }.map { tracker.track($0) }
        sheet.extendStroke(with: rub, predicted: [])
        sheet.endStroke()
        #expect(ink(250..<350) == right, "under a sheet the eraser can't reach")
    }
}

struct LayerStackTests {
    let lower = square(0, 0, 200, 200), upper = square(100, 0, 300, 200), carbon = square(0, 0, 400, 400)

    func grid(_ id: Int, _ outline: [CGPoint]) -> LayerStack.Sheet { .init(id: id, outline: outline, isCarbon: false) }
    func carbonSheet(_ outline: [CGPoint]) -> LayerStack.Sheet { .init(id: 0, outline: outline, isCarbon: true) }

    func targets(_ sheets: [LayerStack.Sheet], erasing: Bool = false) -> [SurfaceID: StrokeMask] {
        Dictionary(uniqueKeysWithValues: LayerStack(sheets: sheets).targets(erasing: erasing).map { ($0.surface, $0.mask) })
    }

    @Test func thePencilMarksWhatIsOnTop() {
        let t = targets([grid(1, lower), grid(2, upper)])
        #expect(t.count == 3)
        let onLowerOnly = CGPoint(x: 50, y: 50), onBoth = CGPoint(x: 150, y: 50), bare = CGPoint(x: 350, y: 50)
        #expect(t[.sheet(1)]!.contains(onLowerOnly))
        #expect(!t[.sheet(1)]!.contains(onBoth))
        #expect(t[.sheet(2)]!.contains(onBoth))
        #expect(t[.paper]!.contains(bare))
        #expect(!t[.paper]!.contains(onBoth))
        #expect(t[.carbonCopy] == nil, "no carbon, no copy")
    }

    @Test func pressingThroughSheetsCopiesOntoThePaper() {
        let t = targets([carbonSheet(carbon), grid(1, lower)])
        let onSheet = CGPoint(x: 50, y: 50), onCarbon = CGPoint(x: 300, y: 300)
        #expect(t[.carbonCopy]!.contains(onSheet))
        #expect(t[.carbonCopy]!.contains(onCarbon))
        #expect(!t[.paper]!.contains(onCarbon), "the carbon covers the paper")
        #expect(!t[.carbonCopy]!.contains(CGPoint(x: 500, y: 50)))
        #expect(t[.sheetCopy(1)] == nil, "the sheet is above the carbon")
    }

    @Test func carbonOverASheetCopiesOntoThatSheet() {
        // Paper, then a grid sheet, then the carbon on top of it.
        let t = targets([grid(1, lower), carbonSheet(carbon)])
        let overSheet = CGPoint(x: 50, y: 50), overPaper = CGPoint(x: 300, y: 300)
        #expect(t[.sheetCopy(1)]!.contains(overSheet))
        #expect(!t[.carbonCopy]!.contains(overSheet), "the sheet is in the way")
        #expect(t[.carbonCopy]!.contains(overPaper))
        #expect(!t[.sheet(1)]!.contains(overSheet), "graphite stays on the carbon")
    }

    @Test func theEraserReachesCopiesOnlyWhereTheyAreBare() {
        let t = targets([carbonSheet(carbon), grid(1, lower)], erasing: true)
        #expect(!t[.carbonCopy]!.contains(CGPoint(x: 300, y: 300)))
        #expect(t[.carbonCopy]!.contains(CGPoint(x: 500, y: 50)))
        #expect(t[.paper]!.contains(CGPoint(x: 500, y: 50)))
        #expect(t[.sheetCopy(1)]!.contains(CGPoint(x: 50, y: 50)))
    }
}

struct PaperSizeTests {
    @Test func aSeriesSizesTurnOnTheirSide() {
        let a3 = PaperSize(series: .a3, landscape: false)
        #expect(a3.sizeMM.width == 297 && a3.sizeMM.height == 420)
        let wide = PaperSize(series: .a3, landscape: true)
        #expect(wide.sizeMM.width == 420 && wide.sizeMM.height == 297)
        #expect(PaperSize(series: .a1, landscape: false).sizeMM.height == 841)
        #expect(PaperSize(series: .b4, landscape: false).sizeMM.width == 257)
    }

    @Test func theDeskLeavesRoomAroundThePaper() {
        let a4 = PaperSize(series: .a4, landscape: false)
        #expect(a4.deskSideMM(minimumMM: 0) == 297 + 120)
        #expect(a4.deskSideMM(minimumMM: 500) == 500, "never smaller than the screen")
    }

    @Test func screenFittedPaperIsTheScreenWithNoDeskAround() {
        let fitted = PaperSize(series: .screen, landscape: true, screenWidthMM: 160, screenHeightMM: 230)
        #expect(fitted.sizeMM.width == 160 && fitted.sizeMM.height == 230, "as the screen was held, not turned")
        #expect(fitted.deskSideMM(minimumMM: 230) == 230)
        #expect(fitted.fitsScreen)
    }

    @Test func nothingMarksTheDeskBeyondThePaper() {
        let paper = square(0, 0, 300, 300)
        let carbon = LayerStack.Sheet(id: 0, outline: square(200, 0, 500, 300), isCarbon: true)
        let t = Dictionary(uniqueKeysWithValues: LayerStack(sheets: [carbon], paper: paper).targets(erasing: false).map { ($0.surface, $0.mask) })
        #expect(t[.paper]!.contains(CGPoint(x: 100, y: 100)))
        #expect(!t[.paper]!.contains(CGPoint(x: 600, y: 100)), "the desk")
        #expect(t[.carbonCopy]!.contains(CGPoint(x: 250, y: 100)))
        #expect(!t[.carbonCopy]!.contains(CGPoint(x: 400, y: 100)), "carbon hanging off the paper copies onto nothing")
    }
}

struct PaperLayerTests {
    @Test func samplesLandOnTheSheetsOwnSurface() {
        let sheet = PaperLayer(id: 1, kind: .grid(.square1), pose: ToolPose(center: CGPoint(x: 1000, y: 1000), angle: .pi / 2))
        // The sheet's top-left corner, turned a quarter, lies up and to the right of its centre.
        let corner = sheet.surfacePoint(CGPoint(x: 1600, y: 400), pixelsPerMillimeter: ppmm)
        #expect(abs(Double(corner.x)) < 1e-6 && abs(Double(corner.y)) < 1e-6)
        let middle = sheet.surfacePoint(CGPoint(x: 1000, y: 1000), pixelsPerMillimeter: ppmm)
        #expect(abs(Double(middle.x) - 600) < 1e-6 && abs(Double(middle.y) - 600) < 1e-6)
        let s = sheet.surfaceSample(StrokeSample(location: CGPoint(x: 1000, y: 1000), azimuth: .pi), pixelsPerMillimeter: ppmm)
        #expect(abs(s.azimuth - .pi / 2) < 1e-9)
        let size = sheet.rasterSize(pixelsPerMillimeter: ppmm)
        #expect(size.width == 1200 && size.height == 1200)
    }

    @Test func aSheetIsPickedUpByItsEdgeOnly() {
        let sheet = PaperLayer(id: 1, kind: .grid(.square1), pose: ToolPose(center: CGPoint(x: 1000, y: 1000), angle: 0))
        let grip = { (p: CGPoint) in sheet.edgeBandContains(p, inner: 120, outer: 40, pixelsPerMillimeter: ppmm) }
        #expect(grip(CGPoint(x: 450, y: 1000)), "just inside the left edge")
        #expect(grip(CGPoint(x: 380, y: 1000)), "just outside it")
        #expect(!grip(CGPoint(x: 1000, y: 1000)), "the middle stays free")
        #expect(!grip(CGPoint(x: 300, y: 1000)))
    }

    @Test func theRoundSheetIsRound() {
        let polar = PaperLayer(id: 1, kind: .grid(.polar), pose: ToolPose(center: .zero, angle: 0))
        let outline = polar.outline(pixelsPerMillimeter: ppmm)
        #expect(outline.count == SheetKind.roundSegments)
        #expect(outline.allSatisfy { abs(hypot(Double($0.x), Double($0.y)) - 600) < 1e-6 })
        #expect(!Polygon.contains(CGPoint(x: 560, y: 560), outline), "the square's corner is not on it")
    }
}

struct GridRulingTests {
    @Test func oneMillimetreSquaresWithHeavierFivesAndTens() {
        let lines = GridRulings.lines(.square1)
        #expect(lines.count == 121 * 2)
        #expect(lines.filter { $0.weight == .bold }.count == 13 * 2)
        #expect(lines.filter { $0.weight == .medium }.count == 12 * 2)
    }

    @Test func isometricLinesStayOnTheSheet() {
        let lines = GridRulings.lines(.isometric)
        let (w, h) = GridPattern.isometric.sizeMM
        #expect(lines.count > 40)
        for line in lines {
            for p in [line.from, line.to] {
                #expect(p.x >= -1e-6 && p.x <= w + 1e-6 && p.y >= -1e-6 && p.y <= h + 1e-6)
            }
        }
        // Three directions only: vertical and ±30°.
        let angles = Set(lines.map { line -> Int in
            var a = atan2(Double(line.to.y - line.from.y), Double(line.to.x - line.from.x)) * 180 / .pi
            if a < 0 { a += 180 }
            return Int(a.rounded()) % 180
        })
        #expect(angles == [90, 30, 150])
    }

    @Test func tracingPaperHasNothingPrinted() {
        for plain in [GridPattern.tracing, .butter] {
            #expect(GridRulings.lines(plain).isEmpty)
            #expect(GridRulings.rings(plain).isEmpty)
            #expect(plain.isPlain)
        }
        #expect(GridPattern.tracing.sizeMM.width == 210 && GridPattern.tracing.sizeMM.height == 297, "A4")
    }

    @Test func polarRingsAndRays() {
        #expect(GridRulings.rings(.polar).count == 12)
        #expect(GridRulings.lines(.polar).count == 24)
        #expect(GridRulings.rings(.square1).isEmpty)
    }
}

struct EdgeScaleTests {
    @Test func ticksFallOnWholeMillimetres() {
        // 2 points per millimetre, starting 3.5 mm before the paper's edge.
        let scale = EdgeScale(startMM: -3.5, mmPerPoint: 0.5, length: 40, paperMM: 297)
        let ticks = scale.ticks
        #expect(ticks.first?.mm == -3)
        #expect(ticks.last?.mm == 16)
        #expect(abs(ticks.first!.at - 1) < 1e-9)
        #expect(ticks.first { $0.mm == 10 }?.weight == .bold)
        #expect(ticks.first { $0.mm == 5 }?.weight == .medium)
        #expect(ticks.first { $0.mm == 7 }?.weight == .fine)
    }

    @Test func thePaperSpanShowsWhereThePaperIs() {
        let scale = EdgeScale(startMM: -10, mmPerPoint: 0.5, length: 100, paperMM: 297)
        #expect(scale.paperSpan == 20...100)
        let past = EdgeScale(startMM: 400, mmPerPoint: 0.5, length: 100, paperMM: 297)
        #expect(past.paperSpan == nil, "all desk")
    }

    @Test func aTurnedPaperRunsBackwards() {
        let scale = EdgeScale(startMM: 50, mmPerPoint: -0.5, length: 40, paperMM: 297)
        #expect(scale.ticks.map(\.mm).first == 50)
        #expect(scale.ticks.map(\.mm).last == 30)
        #expect(scale.paperSpan == 0...40)
    }
}

struct ToneCutTests {
    @Test func aCutAcrossTheSheetLetsOneSidePeelAway() {
        var tone = ToneCut(widthMM: 20, heightMM: 10)
        let all = tone.keptCount
        let peeled1 = tone.peel(at: CGPoint(x: 5, y: 5))
        #expect(!peeled1, "nothing cut away yet: the whole sheet stays")
        tone.cut(from: CGPoint(x: 10, y: -1), to: CGPoint(x: 10, y: 11))
        let peeled2 = tone.peel(at: CGPoint(x: 15, y: 5))
        #expect(peeled2)
        #expect(!tone.isKept(at: CGPoint(x: 15, y: 5)))
        #expect(tone.isKept(at: CGPoint(x: 5, y: 5)))
        #expect(tone.keptCount < all / 2 + all / 10)
    }

    @Test func aDiagonalCutHasNoGapsToSlipThrough() {
        var tone = ToneCut(widthMM: 20, heightMM: 20)
        tone.cut(from: CGPoint(x: -1, y: -1), to: CGPoint(x: 21, y: 21.7))
        let peeled3 = tone.peel(at: CGPoint(x: 15, y: 3))
        #expect(peeled3)
        #expect(tone.isKept(at: CGPoint(x: 3, y: 15)), "the other side stays")
    }

    @Test func cuttingRoundAShapeLiftsJustTheShape() {
        var tone = ToneCut(widthMM: 40, heightMM: 40)
        let ring = (0...64).map { i -> CGPoint in
            let a = Double(i) / 64 * 2 * .pi
            return CGPoint(x: 20 + 8 * cos(a), y: 20 + 8 * sin(a))
        }
        for (a, b) in zip(ring, ring.dropFirst()) { tone.cut(from: a, to: b) }
        let peeled4 = tone.peel(at: CGPoint(x: 20, y: 20))
        #expect(peeled4)
        #expect(!tone.isKept(at: CGPoint(x: 20, y: 20)))
        #expect(tone.isKept(at: CGPoint(x: 2, y: 2)))
        // Or keep the shape and lift what is round it.
        var other = ToneCut(widthMM: 40, heightMM: 40)
        for (a, b) in zip(ring, ring.dropFirst()) { other.cut(from: a, to: b) }
        let peeled5 = other.peel(at: CGPoint(x: 2, y: 2))
        #expect(peeled5)
        #expect(other.isKept(at: CGPoint(x: 20, y: 20)))
        #expect(!other.isKept(at: CGPoint(x: 35, y: 35)))
    }

    @Test func gradationDarkensAcrossTheSheet() {
        #expect(TonePattern.gradation.coverage(atX: 0, width: 100) < TonePattern.gradation.coverage(atX: 100, width: 100))
        let r = TonePattern.dotRadius(coverage: 0.5)
        #expect(abs(Double.pi * r * r / (TonePattern.pitchMM * TonePattern.pitchMM) - 0.5) < 1e-9)
    }
}

struct StampTests {
    @Test func aSheetsDrawingPrintsOntoThePaperWhereItLies() {
        let sheet = DraftingSheet(width: 200, height: 200, pixelsPerMillimeter: ppmm)
        sheet.beginStroke(grade: .b4)
        sheet.extendStroke(with: (0...20).map { StrokeSample(location: CGPoint(x: 20 + Double($0) * 5, y: 50), pressure: 0.8) },
                           predicted: [])
        sheet.endStroke()
        let paper = DraftingSheet(width: 600, height: 600, pixelsPerMillimeter: ppmm)
        // The sheet lies 300 px right and 200 px down on the paper.
        let laid = paper.imprint(sheet.graphite, over: PixelRect(minX: 300, minY: 200, maxX: 500, maxY: 400)) {
            CGPoint(x: Double($0.x) - 300, y: Double($0.y) - 200)
        }
        #expect(laid)
        #expect(paper.graphite.value(x: 370, y: 250) > 0.1)
        #expect(paper.graphite.value(x: 70, y: 50) == 0, "nothing where the sheet isn't")
        #expect(sheet.graphite.value(x: 70, y: 50) > 0.1, "the sheet keeps its drawing")
        #expect(paper.undo())
        #expect(paper.graphite.value(x: 370, y: 250) == 0)
    }

    @Test func nothingDrawnNothingStamped() {
        let paper = DraftingSheet(width: 300, height: 300, pixelsPerMillimeter: ppmm)
        let empty = GraphiteRaster(width: 100, height: 100)
        #expect(!paper.imprint(empty, over: paper.graphite.bounds) { $0 })
        #expect(!paper.canUndo)
    }
}

struct EraserKindTests {
    func sheetWithALine() -> DraftingSheet {
        let sheet = DraftingSheet(width: 300, height: 200, pixelsPerMillimeter: ppmm, paper: PaperTexture(size: 64, seed: 3))
        sheet.beginStroke(grade: .b4)
        sheet.extendStroke(with: (0...40).map { StrokeSample(location: CGPoint(x: 20 + Double($0) * 6.5, y: 100), pressure: 0.8) },
                           predicted: [])
        sheet.endStroke()
        return sheet
    }

    func ink(_ sheet: DraftingSheet) -> Float {
        var total: Float = 0
        for y in 90..<110 { for x in 120..<180 { total += sheet.graphite.value(x: x, y: y) } }
        return total
    }

    func rubOnce(_ sheet: DraftingSheet, _ kind: EraserKind) {
        sheet.beginErasing(kind: kind)
        sheet.extendStroke(with: stride(from: 100.0, through: 200, by: 2).map { StrokeSample(location: CGPoint(x: $0, y: 100)) },
                           predicted: [])
        sheet.endStroke()
    }

    @Test func eachEraserTakesItsOwnShare() {
        let start = ink(sheetWithALine())
        var left: [EraserKind: Float] = [:]
        for kind in EraserKind.allCases {
            let sheet = sheetWithALine()
            rubOnce(sheet, kind)
            left[kind] = ink(sheet) / start
        }
        #expect(left[.electric]! < 0.08, "the electric eraser takes a line clean in one pass")
        #expect(left[.rubber]! > 0.25 && left[.rubber]! < 0.7, "the rubber needs going over")
        #expect(left[.kneaded]! > 0.7, "the kneaded rubber only lightens")
    }

    @Test func clearingTakesAllAndUndoBringsItBack() {
        let sheet = sheetWithALine()
        let before = ink(sheet)
        #expect(sheet.clear())
        #expect(ink(sheet) == 0)
        #expect(sheet.undo())
        #expect(ink(sheet) == before)
        let empty = DraftingSheet(width: 100, height: 100, pixelsPerMillimeter: ppmm)
        #expect(!empty.clear())
    }
}

struct PerspectivePinTests {
    let shapeAt = { (pose: ToolPose) in DeskTool(kind: .ruler, pose: pose).shape(pixelsPerMillimeter: ppmm) }
    let level = ToolPose(center: CGPoint(x: 1000, y: 1000), angle: 0)
    // The ruler is 30 mm wide: its upper edge runs along y = 850.
    let pin = CGPoint(x: 1200, y: 840)

    func distance(_ pose: ToolPose, side: Int) -> Double {
        PinPivot.side(shapeAt(pose), side).measure(pin).out
    }

    @Test func anEdgeNearThePinRestsAgainstIt() throws {
        let side = try #require(PinPivot.contact(shapeAt(level), pin: pin, pixelsPerMillimeter: ppmm))
        #expect(PinPivot.side(shapeAt(level), side).normal.y < -0.99, "the upper edge")
        let settled = PinPivot.settle(level, side: side, pin: pin, shapeAt: shapeAt, pixelsPerMillimeter: ppmm)
        #expect(abs(distance(settled, side: side) - PinPivot.shaftMM * ppmm) < 1e-6)
        #expect(PinPivot.contact(shapeAt(ToolPose(center: CGPoint(x: 1000, y: 1300), angle: 0)), pin: pin,
                                 pixelsPerMillimeter: ppmm) == nil, "too far away")
    }

    @Test func aQuickDragIntoThePinStillTakesTheSideItCameFrom() throws {
        let before = shapeAt(ToolPose(center: CGPoint(x: 1000, y: 1020), angle: 0))
        let after = shapeAt(ToolPose(center: CGPoint(x: 1000, y: 980), angle: 0)) // pin now 3 mm inside
        let side = try #require(PinPivot.contact(after, pin: pin, before: before, pixelsPerMillimeter: ppmm))
        #expect(PinPivot.side(after, side).normal.y < -0.99)
    }

    @Test func swingingTurnsAboutThePinAndKeepsTheEdgeOnIt() throws {
        let side = try #require(PinPivot.contact(shapeAt(level), pin: pin, pixelsPerMillimeter: ppmm))
        let start = PinPivot.settle(level, side: side, pin: pin, shapeAt: shapeAt, pixelsPerMillimeter: ppmm)
        let old = CGPoint(x: 1500, y: 900)
        let turn = 10 * Double.pi / 180
        let dx = Double(old.x - pin.x), dy = Double(old.y - pin.y)
        let new = CGPoint(x: Double(pin.x) + dx * cos(turn) - dy * sin(turn), y: Double(pin.y) + dx * sin(turn) + dy * cos(turn))
        let moved = try #require(PinPivot.pivot(start, side: side, pin: pin, from: old, to: new, shapeAt: shapeAt,
                                                pixelsPerMillimeter: ppmm))
        #expect(abs(moved.angle - turn) < 1e-6)
        #expect(abs(distance(moved, side: side) - PinPivot.shaftMM * ppmm) < 1e-6, "still touching")
    }

    @Test func slidingPastItsEndTakesTheToolOffThePin() throws {
        let side = try #require(PinPivot.contact(shapeAt(level), pin: pin, pixelsPerMillimeter: ppmm))
        let start = PinPivot.settle(level, side: side, pin: pin, shapeAt: shapeAt, pixelsPerMillimeter: ppmm)
        let short = PinPivot.pivot(start, side: side, pin: pin, from: CGPoint(x: 1500, y: 846), to: CGPoint(x: 2000, y: 846),
                                   shapeAt: shapeAt, pixelsPerMillimeter: ppmm)
        #expect(short != nil, "still on the pin")
        let far = PinPivot.pivot(start, side: side, pin: pin, from: CGPoint(x: 1500, y: 846), to: CGPoint(x: 2900, y: 846),
                                 shapeAt: shapeAt, pixelsPerMillimeter: ppmm)
        #expect(far == nil, "slid off its end")
    }
}

struct ParallelRuleTests {
    @Test func theRuleOnlyTravelsUpAndDownLevel() {
        let dragged = ToolPose(center: CGPoint(x: 1234, y: 800), angle: 0.3)
        let kept = ParallelRule.constrain(dragged, boardCentreX: 1000)
        #expect(kept.center.x == 1000 && kept.center.y == 800 && kept.angle == 0)
    }

    @Test func aSetSquareSlidesAlongTheRulesEdge() {
        let rule = DeskTool(kind: .parallelRule, pose: ToolPose(center: CGPoint(x: 1000, y: 1000), angle: 0)).shape(pixelsPerMillimeter: ppmm)
        // A set square pushed down into the rule from above stops on its top edge.
        let square = DeskTool(kind: .setSquare45, pose: ToolPose(center: CGPoint(x: 900, y: 650), angle: 0)).shape(pixelsPerMillimeter: ppmm)
        let push = ToolContact.resolve(ToolContact.polygon(square), against: [ToolContact.polygon(rule)])
        #expect(push.dy < 0 && abs(push.dx) < 1e-6, "pushed straight back up, free to slide sideways")
    }
}

struct ToneScrapeTests {
    func visible(_ tone: ToneCut, inside rect: (Int, Int, Int, Int)) -> Int {
        var n = 0
        for row in rect.1..<rect.3 { for column in rect.0..<rect.2 where tone.shows(row * tone.columns + column) { n += 1 } }
        return n
    }

    /// Strokes back and forth across a band 30 mm long at y = 10 mm.
    func scrape(_ tone: inout ToneCut, strokes: Int, pressure: Double = 0.6) {
        var pass = ToneCut.ScrapePass(tone)
        for k in 0..<strokes {
            let xs = stride(from: 5.0, through: 35, by: 1).map { $0 }
            let path = k % 2 == 0 ? xs : xs.reversed()
            for (a, b) in zip(path, path.dropFirst()) {
                tone.scrape(from: CGPoint(x: a, y: 10), to: CGPoint(x: b, y: 10), pressure: pressure, pass: &pass)
            }
        }
    }

    @Test func eachStrokeLiftsMoreDotsGradually() {
        var tone = ToneCut(widthMM: 40, heightMM: 20)
        let band = (40, 36, 120, 44) // 10..30 mm across, 9..11 mm down: the middle of the blade
        let all = visible(tone, inside: band)
        scrape(&tone, strokes: 1)
        let once = visible(tone, inside: band)
        scrape(&tone, strokes: 2)
        let thrice = visible(tone, inside: band)
        scrape(&tone, strokes: 6)
        let many = visible(tone, inside: band)
        #expect(once < all && once > all / 2, "one stroke only thins it")
        #expect(thrice < once)
        #expect(many < all / 10, "worked over, it comes nearly clean")
    }

    @Test func itLeavesTheFilmAndWhatIsBesideTheBlade() {
        var tone = ToneCut(widthMM: 40, heightMM: 20)
        scrape(&tone, strokes: 12)
        #expect(tone.isKept(at: CGPoint(x: 20, y: 10)), "the film is still there to peel or cut")
        let away = (40, 60, 120, 76) // 15..19 mm down: beyond the blade's edge
        #expect(visible(tone, inside: away) == 80 * 16, "untouched beside it")
    }

    @Test func fineSamplingScrapesNoHarderThanCoarse() {
        var fine = ToneCut(widthMM: 40, heightMM: 20), coarse = ToneCut(widthMM: 40, heightMM: 20)
        var finePass = ToneCut.ScrapePass(fine), coarsePass = ToneCut.ScrapePass(coarse)
        for x in stride(from: 5.0, to: 35, by: 0.25) {
            fine.scrape(from: CGPoint(x: x, y: 10), to: CGPoint(x: x + 0.25, y: 10), pressure: 0.6, pass: &finePass)
        }
        for x in stride(from: 5.0, to: 35, by: 3) {
            coarse.scrape(from: CGPoint(x: x, y: 10), to: CGPoint(x: x + 3, y: 10), pressure: 0.6, pass: &coarsePass)
        }
        let band = (40, 36, 120, 44)
        let a = visible(fine, inside: band), b = visible(coarse, inside: band)
        #expect(a == b, "the same, however the stroke is sampled")
    }
}

struct StampTargetTests {
    let paper = square(0, 0, 1000, 1000)
    func grid(_ id: Int, _ o: [CGPoint]) -> LayerStack.Sheet { .init(id: id, outline: o, isCarbon: false) }

    @Test func aSheetStampsOntoTheSheetJustBelowItAndThePaperElsewhere() {
        // Bottom first: a big tracing sheet, carbon, then the butter paper stamped.
        let lower = square(100, 100, 400, 400), carbon = LayerStack.Sheet(id: 0, outline: square(0, 0, 900, 900), isCarbon: true)
        let top = square(300, 300, 600, 600)
        let stack = LayerStack(sheets: [grid(1, lower), carbon, grid(2, top)], paper: paper)
        let t = Dictionary(uniqueKeysWithValues: stack.stampTargets(from: 2).map { ($0.surface, $0.mask) })
        #expect(t.count == 2, "the tracing sheet below and the paper; not the carbon")
        let overBoth = CGPoint(x: 350, y: 350), overPaper = CGPoint(x: 500, y: 500)
        #expect(t[.sheet(1)]!.contains(overBoth))
        #expect(!t[.paper]!.contains(overBoth), "the sheet below takes it there")
        #expect(t[.paper]!.contains(overPaper))
        #expect(!t[.sheet(1)]!.contains(overPaper))
        #expect(!t[.paper]!.contains(CGPoint(x: 700, y: 700)), "nothing outside the stamped sheet")
    }

    @Test func onlyTheNearestSheetBelowTakesIt() {
        let a = square(0, 0, 500, 500), b = square(100, 100, 500, 500), top = square(200, 200, 400, 400)
        let stack = LayerStack(sheets: [grid(1, a), grid(2, b), grid(3, top)], paper: paper)
        let t = Dictionary(uniqueKeysWithValues: stack.stampTargets(from: 3).map { ($0.surface, $0.mask) })
        let p = CGPoint(x: 300, y: 300)
        #expect(t[.sheet(2)]!.contains(p))
        #expect(!t[.sheet(1)]!.contains(p), "covered by sheet 2")
        #expect(!t[.paper]!.contains(p))
    }

    @Test func sheetFramesRoundTrip() {
        let layer = PaperLayer(id: 1, kind: .grid(.tracing), pose: ToolPose(center: CGPoint(x: 800, y: 600), angle: 0.7))
        let p = CGPoint(x: 1234, y: 456)
        let back = layer.paperPoint(fromSurface: layer.surfacePoint(p, pixelsPerMillimeter: 10), pixelsPerMillimeter: 10)
        #expect(abs(back.x - p.x) < 1e-6 && abs(back.y - p.y) < 1e-6)
    }
}
