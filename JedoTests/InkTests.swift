import CoreGraphics
import Testing
@testable import Jedo

struct InkTests {
    private let ppmm = 10.0

    private func line(_ sheet: DraftingSheet, _ instrument: Instrument, y: Double, pressure: Double = 0.6) {
        sheet.beginStroke(grade: .hb, instrument: instrument)
        sheet.extendStroke(with: stride(from: 20.0, through: 180, by: 2).map {
            StrokeSample(location: CGPoint(x: $0, y: y), pressure: pressure, altitude: .pi / 2, azimuth: 0)
        }, predicted: [])
        sheet.endStroke()
    }

    @Test func aTechnicalPenKeepsItsWidthWhateverThePressure() {
        #expect(InkDynamics.widthMM(.technical(.w035), pressure: 0.1) == 0.35)
        #expect(InkDynamics.widthMM(.technical(.w035), pressure: 1) == 0.35)
    }

    @Test func aGPenSwellsUnderPressureAndAMaruPenStaysFine() {
        let light = InkDynamics.widthMM(.dip(.gPen), pressure: 0.1)
        let firm = InkDynamics.widthMM(.dip(.gPen), pressure: 1)
        #expect(light < 0.15)
        #expect(firm > 1.2)
        #expect(InkDynamics.widthMM(.dip(.maru), pressure: 1) < 0.5)
    }

    @Test func inkIsLaidSolidOverTheGrain() {
        let sheet = DraftingSheet(width: 200, height: 100, pixelsPerMillimeter: ppmm)
        line(sheet, .technicalPen(.w05), y: 50)
        #expect(sheet.graphite.value(x: 100, y: 50) == 2)
        #expect(sheet.graphite.value(x: 100, y: 80) == 0)
    }

    @Test func rubberBarelyTouchesInkButTheElectricEraserGrindsItOff() {
        let sheet = DraftingSheet(width: 200, height: 100, pixelsPerMillimeter: ppmm)
        line(sheet, .technicalPen(.w05), y: 50)
        for kind in [EraserKind.rubber, .kneaded] {
            sheet.beginErasing(kind: kind)
            sheet.extendStroke(with: stride(from: 20.0, through: 180, by: 2).map {
                StrokeSample(location: CGPoint(x: $0, y: 50), pressure: 1, altitude: .pi / 2, azimuth: 0)
            }, predicted: [])
            sheet.endStroke()
        }
        #expect(sheet.graphite.value(x: 100, y: 50) > 1.9)
        for _ in 0..<4 {
            sheet.beginErasing(kind: .electric)
            sheet.extendStroke(with: stride(from: 20.0, through: 180, by: 2).map {
                StrokeSample(location: CGPoint(x: $0, y: 50), pressure: 1, altitude: .pi / 2, azimuth: 0)
            }, predicted: [])
            sheet.endStroke()
        }
        #expect(sheet.graphite.value(x: 100, y: 50) < 1.1)
    }

    @Test func inkCoversGraphiteAndGraphiteDoesNotDarkenInk() {
        let sheet = DraftingSheet(width: 200, height: 100, pixelsPerMillimeter: ppmm)
        line(sheet, .wood, y: 50, pressure: 1)
        line(sheet, .dipPen(.gPen), y: 50, pressure: 1)
        #expect(sheet.graphite.value(x: 100, y: 50) == 2)
        line(sheet, .wood, y: 50, pressure: 1)
        #expect(sheet.graphite.value(x: 100, y: 50) == 2)
        #expect(sheet.canUndo)
        _ = sheet.undo()
        _ = sheet.undo()
        #expect(sheet.graphite.value(x: 100, y: 50) <= 1)
    }

    @Test func inkShowsAsInkAndAsCarbonOnACopy() {
        let sheet = DraftingSheet(width: 200, height: 100, pixelsPerMillimeter: ppmm)
        line(sheet, .technicalPen(.w10), y: 50)
        var pixels = [UInt32](repeating: 0, count: GraphiteRaster.tileArea)
        pixels.withUnsafeMutableBufferPointer {
            sheet.renderGraphite(tile: TileCoord(x: 0, y: 0), rect: sheet.graphite.bounds, into: $0)
        }
        let inked = GraphiteShading.unpack(pixels[50 * GraphiteRaster.tileSize + 100])
        #expect(inked.a > 0.99 && inked.r < 0.05)
        pixels.withUnsafeMutableBufferPointer {
            sheet.renderGraphite(tile: TileCoord(x: 0, y: 0), rect: sheet.graphite.bounds, into: $0,
                                 shading: GraphiteShading.carbonLookup, inkShading: nil)
        }
        #expect(pixels[50 * GraphiteRaster.tileSize + 100] == GraphiteShading.carbonLookup.last)
    }
}

struct StylusTests {
    private func pass(_ sheet: DraftingSheet, _ instrument: Instrument, y: Double, pressure: Double, altitude: Double = .pi / 2) {
        sheet.beginStroke(grade: .b6, instrument: instrument)
        sheet.extendStroke(with: stride(from: 20.0, through: 180, by: 1).map {
            StrokeSample(location: CGPoint(x: $0, y: y), pressure: pressure, altitude: altitude, azimuth: 0)
        }, predicted: [])
        sheet.endStroke()
    }

    @Test func aGroovePressedFirstStaysWhiteUnderShading() {
        let sheet = DraftingSheet(width: 200, height: 100, pixelsPerMillimeter: 10)
        pass(sheet, .stylus, y: 50, pressure: 0.8)
        #expect(sheet.graphite.value(x: 100, y: 50) < 0)
        // Shade over it with the pencil on its side, back and forth.
        for y in stride(from: 30.0, through: 70, by: 4) { pass(sheet, .wood, y: y, pressure: 0.9, altitude: 0.2) }
        #expect(sheet.graphite.value(x: 100, y: 50) < 0)
        #expect(sheet.graphite.value(x: 100, y: 40) > 0.2)
    }

    @Test func inkFillsTheGrooveAndTheElectricEraserFlattensIt() {
        let sheet = DraftingSheet(width: 200, height: 100, pixelsPerMillimeter: 10)
        pass(sheet, .stylus, y: 50, pressure: 0.8)
        for _ in 0..<3 {
            sheet.beginErasing(kind: .electric)
            sheet.extendStroke(with: stride(from: 20.0, through: 180, by: 2).map { StrokeSample(location: CGPoint(x: $0, y: 50), pressure: 1) },
                               predicted: [])
            sheet.endStroke()
        }
        #expect(sheet.graphite.value(x: 100, y: 50) == 0)
        pass(sheet, .stylus, y: 50, pressure: 0.8)
        pass(sheet, .technicalPen(.w05), y: 50, pressure: 0.5)
        #expect(sheet.graphite.value(x: 100, y: 50) == 2)
    }
}
