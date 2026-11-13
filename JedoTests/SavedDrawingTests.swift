import CoreGraphics
import Foundation
import Testing
@testable import Jedo

struct SavedDrawingTests {
    private func raster(_ side: Int, marks: [(TileCoord, Float)]) -> GraphiteRaster {
        var r = GraphiteRaster(width: side, height: side)
        for (coord, value) in marks {
            var tile = [Float](repeating: 0, count: GraphiteRaster.tileArea)
            tile[5] = value
            tile[GraphiteRaster.tileArea - 1] = value / 2
            r.setTile(coord, tile)
        }
        return r
    }

    private func drawing() -> DrawingState {
        var tone = ToneCut(widthMM: 10, heightMM: 8)
        tone.cut(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 9, y: 1))
        var pass = ToneCut.ScrapePass(tone)
        tone.scrape(from: CGPoint(x: 2, y: 4), to: CGPoint(x: 8, y: 4), pressure: 1, pass: &pass)
        let grid = PaperLayer(id: 3, kind: .grid(.butter), pose: ToolPose(center: CGPoint(x: 400, y: 300), angle: 0.4),
                              pieceMM: [CGPoint(x: -150, y: -150), CGPoint(x: 0, y: -150), CGPoint(x: 0, y: 150), CGPoint(x: -150, y: 150)])
        let size = grid.rasterSize(pixelsPerMillimeter: 2)
        return DrawingState(
            paper: PaperSize(series: .screen, landscape: true, screenWidthMM: 260.5, screenHeightMM: 195.25),
            pixelsPerMillimeter: 2, deskSide: 600,
            paperGraphite: raster(600, marks: [(TileCoord(x: 1, y: 2), 0.7), (TileCoord(x: 4, y: 0), 0.2)]),
            carbonCopy: raster(600, marks: [(TileCoord(x: 0, y: 0), 0.5)]),
            sheets: [
                .init(layer: PaperLayer(id: 0, kind: .carbon, pose: ToolPose(center: CGPoint(x: 300, y: 300), angle: 0)),
                      hidden: false, graphite: nil, copies: nil, tone: nil),
                .init(layer: grid, hidden: true,
                      graphite: raster(max(size.width, size.height), marks: []).isEmpty
                        ? { var r = GraphiteRaster(width: size.width, height: size.height)
                            r.setTile(TileCoord(x: 1, y: 1), [Float](repeating: 0.3, count: GraphiteRaster.tileArea)); return r }()
                        : nil,
                      copies: GraphiteRaster(width: size.width, height: size.height), tone: nil),
                .init(layer: PaperLayer(id: 4, kind: .tone(.gradation), pose: ToolPose(center: CGPoint(x: 100, y: 120), angle: -1)),
                      hidden: false, graphite: nil, copies: nil, tone: tone),
            ],
            nextLayerID: 5, pins: [CGPoint(x: 12.5, y: 40), CGPoint(x: 580, y: 2)])
    }

    @Test func aDrawingComesBackAsItWasSaved() throws {
        let saved = drawing()
        let back = try DrawingStore.decode(DrawingStore.encode(saved))
        #expect(back.paper == saved.paper)
        #expect(back.pixelsPerMillimeter == saved.pixelsPerMillimeter)
        #expect(back.deskSide == 600)
        #expect(back.paperGraphite.tiles == saved.paperGraphite.tiles)
        #expect(back.carbonCopy.tiles == saved.carbonCopy.tiles)
        #expect(back.sheets.map(\.layer) == saved.sheets.map(\.layer))
        #expect(back.sheets.map(\.hidden) == [false, true, false])
        #expect(back.sheets[1].graphite?.tiles == saved.sheets[1].graphite?.tiles)
        #expect(back.sheets[1].graphite?.width == saved.sheets[1].graphite?.width)
        #expect(back.sheets[2].tone == saved.sheets[2].tone)
        #expect(back.nextLayerID == 5)
        #expect(back.pins == saved.pins)
    }

    @Test func everySheetKindHasACodeThatReadsBack() {
        let kinds: [SheetKind] = [.carbon] + GridPattern.allCases.map { .grid($0) } + TonePattern.allCases.map { .tone($0) }
        for kind in kinds { #expect(SheetKind(code: kind.code) == kind) }
        #expect(Set(kinds.map(\.code)).count == kinds.count)
    }

    @Test func aDamagedFileIsNotTakenForADrawing() throws {
        var data = try DrawingStore.encode(drawing())
        data = data.prefix(data.count / 2)
        #expect((try? DrawingStore.decode(data)) == nil)
        #expect((try? DrawingStore.decode(Data("not a drawing".utf8))) == nil)
    }

    @Test func savingAndLoadingGoThroughAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jedo-\(UUID()).jedo")
        defer { DrawingStore.remove(at: url) }
        try DrawingStore.save(drawing(), to: url)
        #expect(DrawingStore.load(from: url)?.sheets.count == 3)
        DrawingStore.remove(at: url)
        #expect(DrawingStore.load(from: url) == nil)
    }
}
