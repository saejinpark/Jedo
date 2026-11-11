import CoreGraphics
import Testing
@testable import Jedo

struct DraftingSheetTests {
    static let paper = PaperTexture(size: 64, seed: 3)
    let ppmm = 264.0 / 25.4

    func makeSheet(budget: Int = DraftingSheet.defaultHistoryBudget) -> DraftingSheet {
        DraftingSheet(width: 400, height: 300, pixelsPerMillimeter: ppmm, paper: Self.paper, historyBudgetBytes: budget)
    }

    func line(_ sheet: DraftingSheet, grade: PencilGrade = .b2, from a: CGPoint, to b: CGPoint, pressure: Double = 0.6) {
        let steps = 40
        let samples = (0...steps).map { i -> StrokeSample in
            let t = Double(i) / Double(steps)
            return StrokeSample(location: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), pressure: pressure)
        }
        sheet.beginStroke(grade: grade, at: samples[0])
        sheet.extendStroke(with: Array(samples.dropFirst()), predicted: [])
        sheet.endStroke()
    }

    func totalInk(_ sheet: DraftingSheet) -> Float {
        sheet.graphite.tiles.values.reduce(0) { $0 + $1.reduce(0, +) }
    }

    @Test func aStrokeLeavesGraphiteOnlyAlongItsPath() {
        let sheet = makeSheet()
        line(sheet, from: CGPoint(x: 20, y: 50), to: CGPoint(x: 380, y: 50))
        let along = (20..<380).map { x in (48...52).map { sheet.graphite.value(x: x, y: $0) }.max()! }
        #expect(along.filter { $0 > 0 }.count > 340, "the line is continuous")
        #expect((0..<400).allSatisfy { sheet.graphite.value(x: $0, y: 150) == 0 })
    }

    @Test func strokeShowsWhileDrawingButOnlyCommitsAtTheEnd() {
        let sheet = makeSheet()
        sheet.beginStroke(grade: .b4, at: StrokeSample(location: CGPoint(x: 100, y: 100)))
        sheet.extendStroke(with: [StrokeSample(location: CGPoint(x: 200, y: 100))], predicted: [])
        #expect(sheet.isDrawing)
        #expect(sheet.graphite.isEmpty)
        #expect(sheet.displayedDensity(x: 150, y: 100) > 0)
        sheet.endStroke()
        #expect(!sheet.isDrawing)
        #expect(sheet.graphite.value(x: 150, y: 100) == sheet.displayedDensity(x: 150, y: 100))
    }

    @Test func predictionIsDrawnThenReplaced() {
        let sheet = makeSheet()
        sheet.beginStroke(grade: .b2, at: StrokeSample(location: CGPoint(x: 50, y: 200)))
        sheet.extendStroke(with: [StrokeSample(location: CGPoint(x: 100, y: 200))],
                           predicted: [StrokeSample(location: CGPoint(x: 140, y: 200))])
        let predictedSpot = (198...202).map { sheet.displayedDensity(x: 130, y: $0) }.max()!
        #expect(predictedSpot > 0)
        sheet.extendStroke(with: [StrokeSample(location: CGPoint(x: 105, y: 200))], predicted: [])
        #expect((198...202).allSatisfy { sheet.displayedDensity(x: 130, y: $0) == 0 }, "stale prediction is gone")
        sheet.endStroke()
        #expect((198...202).allSatisfy { sheet.graphite.value(x: 130, y: $0) == 0 }, "prediction never commits")
    }

    @Test func provisionalSamplesShowButOnlyFinalOnesCommit() {
        let sheet = makeSheet()
        sheet.beginStroke(grade: .b2)
        sheet.extendStroke(with: [], predicted: [StrokeSample(location: CGPoint(x: 50, y: 50)),
                                                 StrokeSample(location: CGPoint(x: 90, y: 50))])
        #expect((48...52).contains { sheet.displayedDensity(x: 70, y: $0) > 0 })
        sheet.endStroke()
        #expect(sheet.graphite.isEmpty)
        #expect(!sheet.canUndo, "nothing was laid, so there is nothing to undo")
    }

    @Test func goingOverALineAgainDarkensIt() {
        let sheet = makeSheet()
        let a = CGPoint(x: 20, y: 80), b = CGPoint(x: 380, y: 80)
        line(sheet, from: a, to: b)
        let once = totalInk(sheet)
        line(sheet, from: a, to: b)
        let twice = totalInk(sheet)
        line(sheet, from: a, to: b)
        let thrice = totalInk(sheet)
        #expect(twice > once * 1.2)
        #expect(thrice > twice)
        #expect(thrice - twice < twice - once, "each pass adds less")
    }

    /// Mean density over the middle of a band of overlapping strokes.
    func bandDensity(_ sheet: DraftingSheet) -> Float {
        var total: Float = 0, count = 0
        for y in 120..<140 { for x in 100..<300 { total += sheet.graphite.value(x: x, y: y); count += 1 } }
        return total / Float(count)
    }

    func scribbleBand(_ sheet: DraftingSheet, grade: PencilGrade, pressure: Double, passes: Int) {
        for _ in 0..<passes {
            for y in stride(from: 110.0, through: 150, by: 2) {
                line(sheet, grade: grade, from: CGPoint(x: 80, y: y), to: CGPoint(x: 320, y: y), pressure: pressure)
            }
        }
    }

    @Test func sixBPressedHardAndGoneOverTurnsBlack() {
        let sheet = makeSheet()
        scribbleBand(sheet, grade: .b6, pressure: 1, passes: 3)
        #expect(bandDensity(sheet) > 0.97)
    }

    @Test func hbNeverTurnsBlackHoweverHardYouPress() {
        let sheet = makeSheet()
        scribbleBand(sheet, grade: .hb, pressure: 1, passes: 4)
        let d = bandDensity(sheet)
        #expect(d > 0.6)
        #expect(d <= Float(PencilGrade.hb.parameters.maxDensity))
    }

    @Test func gentlerGrainStylesLeaveLessPaperShowing() {
        var previous: Float = 0
        for style in GrainStyle.all {
            let sheet = makeSheet()
            sheet.grainStyle = style
            scribbleBand(sheet, grade: .b2, pressure: 0.4, passes: 1)
            let d = bandDensity(sheet)
            #expect(d > previous, "\(style.name) should fill more of the tooth")
            previous = d
        }
    }

    @Test func softerGradesLayMoreGraphite() {
        var previous: Float = 0
        for grade in PencilGrade.allCases {
            let sheet = makeSheet()
            line(sheet, grade: grade, from: CGPoint(x: 20, y: 80), to: CGPoint(x: 380, y: 80))
            let ink = totalInk(sheet)
            #expect(ink > previous, "\(grade.label) should lay more than the grade before")
            previous = ink
        }
    }

    @Test func undoRestoresTheSheetExactlyAndRedoReappliesIt() {
        let sheet = makeSheet()
        line(sheet, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 390, y: 290))
        let afterFirst = sheet.graphite.tiles
        line(sheet, grade: .b6, from: CGPoint(x: 10, y: 290), to: CGPoint(x: 390, y: 10))
        let afterSecond = sheet.graphite.tiles
        #expect(afterSecond != afterFirst)

        #expect(sheet.undo())
        #expect(sheet.graphite.tiles == afterFirst)
        #expect(sheet.undo())
        #expect(sheet.graphite.isEmpty)
        #expect(!sheet.undo())

        #expect(sheet.redo())
        #expect(sheet.graphite.tiles == afterFirst)
        #expect(sheet.redo())
        #expect(sheet.graphite.tiles == afterSecond)
        #expect(!sheet.redo())
    }

    @Test func drawingAfterUndoDropsRedo() {
        let sheet = makeSheet()
        line(sheet, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 10))
        sheet.undo()
        line(sheet, from: CGPoint(x: 10, y: 100), to: CGPoint(x: 200, y: 100))
        #expect(!sheet.canRedo)
        #expect(sheet.canUndo)
    }

    @Test func cancelledStrokeLeavesNoTraceAndNoUndoStep() {
        let sheet = makeSheet()
        sheet.beginStroke(grade: .b2, at: StrokeSample(location: CGPoint(x: 10, y: 10)))
        sheet.extendStroke(with: [StrokeSample(location: CGPoint(x: 100, y: 100))], predicted: [])
        sheet.cancelStroke()
        #expect(sheet.graphite.isEmpty)
        #expect(!sheet.canUndo)
        #expect(sheet.displayedDensity(x: 50, y: 50) == 0)
    }

    @Test func undoIsUnavailableMidStroke() {
        let sheet = makeSheet()
        line(sheet, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 10))
        sheet.beginStroke(grade: .b2, at: StrokeSample(location: CGPoint(x: 10, y: 50)))
        #expect(!sheet.canUndo)
        #expect(!sheet.undo())
        sheet.endStroke()
        #expect(sheet.canUndo)
    }

    @Test func historyStaysInsideItsBudget() {
        let budget = GraphiteRaster.bytesPerTile * 12
        let sheet = makeSheet(budget: budget)
        for i in 0..<20 {
            line(sheet, from: CGPoint(x: 10, y: 10 + Double(i) * 14), to: CGPoint(x: 390, y: 10 + Double(i) * 14))
        }
        #expect(sheet.historyBytes <= budget)
        var undone = 0
        while sheet.undo() { undone += 1 }
        #expect(undone > 0 && undone < 20)
    }

    @Test func reportsWhatNeedsRedrawing() {
        let sheet = makeSheet()
        _ = sheet.takeDirtyRegions()
        line(sheet, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 10))
        let dirty = sheet.takeDirtyRegions()
        #expect(dirty.keys.contains(TileCoord(x: 0, y: 0)))
        #expect(!dirty.keys.contains(TileCoord(x: 2, y: 2)))
        #expect(sheet.takeDirtyRegions().isEmpty, "asking again returns nothing new")
        sheet.undo()
        #expect(sheet.takeDirtyRegions().keys.contains(TileCoord(x: 0, y: 0)))
    }

    @Test func rendersGraphiteAsPremultipliedPixels() {
        let sheet = makeSheet()
        line(sheet, grade: .b6, from: CGPoint(x: 10, y: 20), to: CGPoint(x: 120, y: 20), pressure: 1)
        var pixels = [UInt32](repeating: 0xDEAD_BEEF, count: GraphiteRaster.tileArea)
        let coord = TileCoord(x: 0, y: 0)
        pixels.withUnsafeMutableBufferPointer {
            sheet.renderGraphite(tile: coord, rect: sheet.graphite.rect(of: coord), into: $0)
        }
        let blank = pixels[100 * GraphiteRaster.tileSize + 60]
        #expect(blank == 0, "untouched paper is fully transparent")
        let inked = (18...22).map { pixels[$0 * GraphiteRaster.tileSize + 60] }.max { ($0 >> 24) < ($1 >> 24) }!
        let (r, g, b, a) = GraphiteShading.unpack(inked)
        #expect(a > 0.4)
        #expect(r <= a && g <= a && b <= a, "premultiplied")
    }
}

struct GraphiteShadingTests {
    @Test func densityDarkensMonotonically() {
        let paper = GraphiteShading.pack(r: 0.96, g: 0.95, b: 0.92, a: 1)
        var previous = 2.0
        for level in stride(from: 0, to: GraphiteShading.levels, by: 64) {
            let c = GraphiteShading.unpack(GraphiteShading.composite(paper: paper, graphite: GraphiteShading.lookup[level]))
            let luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
            #expect(luminance <= previous)
            previous = luminance
        }
    }

    @Test func zeroDensityIsInvisibleAndFullIsGraphite() {
        #expect(GraphiteShading.lookup.first == 0)
        let full = GraphiteShading.unpack(GraphiteShading.lookup.last!)
        #expect(full.a == 1)
        #expect(abs(full.r - GraphiteShading.graphite.r) < 0.01)
    }

    @Test func paperIsWarmWhiteAndItsToothFollowsTheStyle() {
        var previousSpread = 1.0
        for style in GrainStyle.all {
            let pixels = GraphiteShading.paperPixels(PaperTexture(size: 64, seed: 5), relief: style.paperRelief)
            let colours = pixels.map(GraphiteShading.unpack)
            #expect(colours.allSatisfy { $0.a == 1 && $0.r > 0.9 && $0.r >= $0.b })
            let spread = colours.map(\.g).max()! - colours.map(\.g).min()!
            #expect(spread < 0.08)
            #expect(spread <= previousSpread, "\(style.name) should be no rougher than the style before")
            previousSpread = spread
        }
    }
}
