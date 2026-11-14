import CoreGraphics
import Testing
@testable import Jedo

struct CarbonTests {
    @Test func aCopyKeepsTheColourItWasMadeIn() {
        var v = CarbonPalette.lay(base: 0, stroke: 0.6, index: 2)
        #expect(CarbonPalette.split(v).index == 2)
        #expect(abs(CarbonPalette.split(v).density - 0.6) < 1e-6)
        v = CarbonPalette.lay(base: v, stroke: 0.2, index: 3)
        #expect(CarbonPalette.split(v).index == 2)
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
