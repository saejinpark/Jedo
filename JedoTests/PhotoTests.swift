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
        #expect(CarbonPalette.colours.count == CarbonPalette.firstCube + 512)
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
