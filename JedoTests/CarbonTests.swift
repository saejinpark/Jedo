import CoreGraphics
import Testing
@testable import Jedo

struct CarbonTests {
    @Test func aCopyKeepsTheColourItWasMadeIn() {
        var v = CarbonPalette.lay(base: 0, stroke: 0.6, index: 2)
        #expect(CarbonPalette.split(v).index == 2)
        #expect(abs(CarbonPalette.split(v).density - 0.6) < 1e-6)
        v = CarbonPalette.lay(base: v, stroke: 0.2, index: 3)
        #expect(CarbonPalette.split(v).index == 2, "a faint fringe leaves the colour under it")
        let over = CarbonPalette.lay(base: v, stroke: 0.6, index: 4)
        #expect(CarbonPalette.split(over).index == 4, "pressed again on top, the new colour shows")
        v = CarbonPalette.erase(base: v, lift: 0.5)
        #expect(CarbonPalette.split(v).index == 2)
        #expect(CarbonPalette.split(v).density < 0.4)
        // Copies saved before colours read as the classic navy.
        #expect(CarbonPalette.split(0.7).index == 0)
    }

    @Test func gradientsRunAcrossTheSheetAndSolidsDoNot() {
        #expect(CarbonInk.red.paletteIndex(at: 0) == CarbonInk.red.paletteIndex(at: 1))
        #expect(CarbonInk.rainbow.paletteIndex(at: 0) != CarbonInk.rainbow.paletteIndex(at: 1))
        for ink in CarbonInk.allCases {
            for t in stride(from: 0.0, through: 1.0, by: 0.1) {
                #expect(CarbonPalette.colours.indices.contains(ink.paletteIndex(at: t)))
            }
        }
    }

    @Test func clothPrintsRepeatAndHoldMoreThanOneColour() {
        for ink in CarbonInk.allCases where ink.isPattern {
            var seen: Set<Int> = []
            for x in stride(from: 0.25, to: 40, by: 0.5) {
                for y in stride(from: 0.25, to: 40, by: 0.5) { seen.insert(ink.printIndex(atMM: x, y)) }
            }
            #expect(seen.count >= 2, "\(ink)")
            // Every print here repeats within 120 mm each way.
            #expect(ink.printIndex(atMM: 3.3, 7.7) == ink.printIndex(atMM: 123.3, 127.7), "\(ink)")
            #expect(!ink.isPlain && !ink.isGradient)
        }
        #expect(CarbonInk.red.isPlain && !CarbonInk.sea.isPlain)
    }

    @Test func houndstoothIsATwoOverTwoTwillOfFourAndFour() {
        // Along the diagonal of the dark square everything is dark; of the light square, light.
        let dark = CarbonInk.houndstooth.printIndex(atMM: 0.7, 0.7), light = CarbonInk.houndstooth.printIndex(atMM: 6.7, 6.7)
        #expect(dark != light)
        #expect(CarbonInk.houndstooth.printIndex(atMM: 2.2, 3.7) == dark)
        #expect(CarbonInk.houndstooth.printIndex(atMM: 8.2, 9.7) == light)
    }

    @Test func pressingThroughCarbonLaysItsColour() {
        let sheet = DraftingSheet(width: 200, height: 100, pixelsPerMillimeter: 10, isCarbonCopy: true)
        sheet.beginStroke(grade: .b6, instrument: .dipPen(.gPen), colour: { x, _ in x < 100 ? 2 : 3 })
        sheet.extendStroke(with: stride(from: 20.0, through: 180, by: 2).map { StrokeSample(location: CGPoint(x: $0, y: 50), pressure: 0.8) },
                           predicted: [])
        sheet.endStroke()
        #expect(CarbonPalette.split(sheet.graphite.value(x: 50, y: 50)).index == 2)
        #expect(CarbonPalette.split(sheet.graphite.value(x: 150, y: 50)).index == 3)
        #expect(CarbonPalette.split(sheet.graphite.value(x: 150, y: 50)).density > 0.2)
    }

    @Test func aStampThroughCarbonGoesToTheCopyInItsColour() {
        let square = { (x0: Double, y0: Double, x1: Double, y1: Double) in
            [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
        }
        let stack = LayerStack(sheets: [
            .init(id: 0, outline: square(0, 0, 50, 100), isCarbon: true),
            .init(id: 2, outline: square(0, 0, 100, 100), isCarbon: false),
        ], paper: square(0, 0, 200, 200))
        let routes = stack.stampRoutes(from: 2)
        let plain = routes.first { $0.surface == .paper }!
        let copy = routes.first { $0.surface == .carbonCopy }!
        #expect(copy.carbon == 0)
        #expect(copy.mask.contains(CGPoint(x: 25, y: 50)) && !plain.mask.contains(CGPoint(x: 25, y: 50)))
        #expect(plain.mask.contains(CGPoint(x: 75, y: 50)) && !copy.mask.contains(CGPoint(x: 75, y: 50)))
    }
}

struct RollerTests {
    @Test func theRollerLaysABroadBandOnlyOnCarbonCopies() {
        let copy = DraftingSheet(width: 600, height: 400, pixelsPerMillimeter: 10, isCarbonCopy: true)
        copy.beginStroke(grade: .hb, instrument: .roller, colour: { _, _ in 3 })
        copy.extendStroke(with: stride(from: 100.0, through: 500, by: 5).map { StrokeSample(location: CGPoint(x: $0, y: 200), pressure: 0.8) },
                          predicted: [])
        copy.endStroke()
        // 30 mm wide: 12 mm off the line is still rolled.
        let (index, density) = CarbonPalette.split(copy.graphite.value(x: 300, y: 320))
        #expect(index == 3 && density > 0.7)
        #expect(copy.graphite.value(x: 300, y: 370) == 0)

        let plain = DraftingSheet(width: 600, height: 400, pixelsPerMillimeter: 10)
        plain.beginStroke(grade: .hb, instrument: .roller)
        plain.extendStroke(with: [StrokeSample(location: CGPoint(x: 300, y: 200), pressure: 1)], predicted: [])
        plain.endStroke()
        #expect(plain.graphite.value(x: 300, y: 200) == 0)
    }
}

struct RollerShapeTests {
    @Test func aRolledBandIsSquareEndedAndAsWideAsTheRoller() {
        let ppmm = 10.0
        let copy = DraftingSheet(width: 800, height: 600, pixelsPerMillimeter: ppmm, isCarbonCopy: true)
        copy.beginStroke(grade: .hb, instrument: .roller, colour: { _, _ in 2 })
        copy.extendStroke(with: stride(from: 200.0, through: 600, by: 4).map { StrokeSample(location: CGPoint(x: $0, y: 300), pressure: 1) },
                          predicted: [])
        copy.endStroke()
        let half = RollerDynamics.widthMM / 2 * ppmm
        // Full strength right to the band's edge across the travel...
        #expect(CarbonPalette.split(copy.graphite.value(x: 400, y: Int(300 + half - 3))).density > 0.8)
        #expect(copy.graphite.value(x: 400, y: Int(300 + half + 3)) == 0)
        // ...and square at the end: the corner is as full as the middle.
        #expect(CarbonPalette.split(copy.graphite.value(x: 596, y: Int(300 - half + 3))).density > 0.8)
        #expect(copy.graphite.value(x: 640, y: 300) == 0)
    }

    @Test func rollingBackKeepsTheAxle() {
        var spacer = DabSpacer()
        _ = spacer.append(StrokeSample(location: .zero), spacing: { _ in 1 })
        spacer.steer(toward: StrokeSample(location: CGPoint(x: 10, y: 0)), keep: 0.8)
        _ = spacer.append(StrokeSample(location: CGPoint(x: 10, y: 0)), spacing: { _ in 1 })
        spacer.steer(toward: StrokeSample(location: CGPoint(x: 0, y: 0)), keep: 0.8)
        #expect(abs(spacer.heading!.x) > 0.99)
    }
}

struct CarbonPieceTests {
    private func square(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    @Test func everyPieceOfCarbonCopiesWhereItLies() {
        let paper = square(0, 0, 1000, 1000)
        let stack = LayerStack(sheets: [
            .init(id: 5, outline: square(100, 100, 300, 300), isCarbon: true),
            .init(id: 6, outline: square(500, 500, 700, 700), isCarbon: true),
            .init(id: 7, outline: square(0, 0, 1000, 1000), isCarbon: false),
        ], paper: paper)
        let copy = Dictionary(uniqueKeysWithValues: stack.targets(erasing: false).map { ($0.surface, $0.mask) })[.carbonCopy]!
        #expect(copy.contains(CGPoint(x: 200, y: 200)))
        #expect(copy.contains(CGPoint(x: 600, y: 600)))
        #expect(!copy.contains(CGPoint(x: 400, y: 400)), "bare between the pieces")
        #expect(copy.coverage(PixelRect(minX: 350, minY: 350, maxX: 450, maxY: 450)) == .none)
        #expect(stack.carbonsTopFirst.map(\.id) == [6, 5])
    }
}
