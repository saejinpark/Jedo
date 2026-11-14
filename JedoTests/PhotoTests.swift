import CoreGraphics
import Foundation
import Testing
@testable import Jedo

struct PhotoTests {
    @Test func aPhotoIsPrintedSixByFourAndSavedByCode() {
        let wide = PhotoRef(id: "abc", pixelWidth: 4032, pixelHeight: 3024)
        #expect(wide.widthMM == 152 && wide.heightMM == 114)
        let tall = PhotoRef(id: "abc", pixelWidth: 1000, pixelHeight: 2000)
        #expect(tall.heightMM == 152 && tall.widthMM == 76)
        #expect(PhotoRef(code: wide.code) == wide)
        #expect(SheetKind(code: SheetKind.photo(wide).code) == .photo(wide))
        #expect(PhotoRef(code: "photo.x") == nil)
    }

    @Test func photoColoursFindTheirNearestEntry() {
        let red = CarbonPalette.cubeIndex((1, 0, 0)), white = CarbonPalette.cubeIndex((1, 1, 1))
        #expect(CarbonPalette.colours[red] == (1, 0, 0))
        #expect(CarbonPalette.colours[white] == (1, 1, 1))
        #expect(CarbonPalette.colours.count == CarbonPalette.firstCube + 4096)
        // A copy in a cube colour keeps it, with density beside it.
        let v = CarbonPalette.lay(base: 0, stroke: 0.7, index: red)
        #expect(CarbonPalette.split(v).index == red)
        #expect(abs(CarbonPalette.split(v).density - 0.7) < 1e-3)
    }

    @Test func pixelsAreReadByFraction() {
        // 2 × 1: red then blue.
        let p = PhotoPixels(width: 2, height: 1, rgba: [255, 0, 0, 255, 0, 0, 255, 255])
        #expect(p.colour(u: 0.1, v: 0.5)! == (1, 0, 0))
        #expect(p.colour(u: 0.9, v: 0.5)! == (0, 0, 1))
        #expect(p.colour(u: 1.2, v: 0.5) == nil)
    }

    @Test func aPhotoUsedAsCarbonTakesNoPencilAndCopiesThrough() {
        var layer = PaperLayer(id: 4, kind: .photo(PhotoRef(id: "p", widthMM: 100, heightMM: 80)),
                               pose: ToolPose(center: CGPoint(x: 500, y: 500), angle: 0))
        #expect(!layer.isCarbon && layer.kind.takesPencil)
        layer.photoCarbon = true
        #expect(layer.isCarbon)
        let stack = LayerStack(sheets: [.init(id: 4, outline: layer.outline(pixelsPerMillimeter: 1), isCarbon: true)],
                               paper: [CGPoint(x: 0, y: 0), CGPoint(x: 1000, y: 0), CGPoint(x: 1000, y: 1000), CGPoint(x: 0, y: 1000)])
        let targets = Dictionary(uniqueKeysWithValues: stack.targets(erasing: false).map { ($0.surface, $0.mask) })
        #expect(targets[.sheet(4)] == nil)
        #expect(targets[.carbonCopy]!.contains(CGPoint(x: 500, y: 500)))
        #expect(stack.pressingCarbon == 4)
    }

    @Test func gluedAndCarbonPhotosAreSaved() throws {
        var layer = PaperLayer(id: 3, kind: .photo(PhotoRef(id: "q", widthMM: 90, heightMM: 60)),
                               pose: ToolPose(center: CGPoint(x: 100, y: 100), angle: 0.2))
        layer.glued = true
        let size = layer.rasterSize(pixelsPerMillimeter: 2)
        let state = DrawingState(paper: PaperSize(series: .a4, landscape: false), pixelsPerMillimeter: 2, deskSide: 800,
                                 paperGraphite: GraphiteRaster(width: 800, height: 800), carbonCopy: GraphiteRaster(width: 800, height: 800),
                                 sheets: [.init(layer: layer, hidden: false, graphite: GraphiteRaster(width: size.width, height: size.height),
                                                copies: nil, tone: nil)],
                                 nextLayerID: 4, pins: [])
        let back = try DrawingStore.decode(DrawingStore.encode(state))
        #expect(back.sheets[0].layer == layer)
    }
}

@MainActor
struct PDFPageTests {
    @Test func anA4PDFPageComesInAtItsRealSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jedo-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 100, y: 700, width: 200, height: 40))
        ctx.endPDFPage()
        ctx.closePDF()
        let page = try #require(PhotoStore.addPDF(at: url))
        #expect(page.widthMM == 210 && page.heightMM == 297)
        let image = try #require(PhotoStore.image(page.id))
        #expect(image.width > 1500 && image.height > image.width)
        // Dark where the bar was drawn (near the top), white elsewhere.
        let pixels = try #require(PhotoStore.pixels(page.id))
        #expect(pixels.colour(u: 0.33, v: 0.145)!.r < 0.2)
        #expect(pixels.colour(u: 0.8, v: 0.8)!.r > 0.9)
        PhotoStore.keepOnly([])
    }
}
