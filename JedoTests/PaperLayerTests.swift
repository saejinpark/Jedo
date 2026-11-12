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
    }

    @Test func theDeskLeavesRoomAroundThePaper() {
        let a4 = PaperSize(series: .a4, landscape: false)
        #expect(a4.deskSideMM(minimumMM: 0) == 297 + 120)
        #expect(a4.deskSideMM(minimumMM: 500) == 500, "never smaller than the screen")
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

    @Test func polarRingsAndRays() {
        #expect(GridRulings.rings(.polar).count == 12)
        #expect(GridRulings.lines(.polar).count == 24)
        #expect(GridRulings.rings(.square1).isEmpty)
    }
}
