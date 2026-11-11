import CoreGraphics
import Testing
@testable import Jedo

struct PixelRectTests {
    @Test func intersectionAndUnion() {
        let a = PixelRect(minX: 0, minY: 0, maxX: 10, maxY: 10)
        let b = PixelRect(minX: 5, minY: 8, maxX: 20, maxY: 30)
        #expect(a.intersection(b) == PixelRect(minX: 5, minY: 8, maxX: 10, maxY: 10))
        #expect(a.union(b) == PixelRect(minX: 0, minY: 0, maxX: 20, maxY: 30))
        #expect(a.intersection(PixelRect(minX: 10, minY: 0, maxX: 12, maxY: 5)).isEmpty)
        #expect(PixelRect.empty.union(b) == b)
    }
}

struct GraphiteRasterTests {
    @Test func untouchedPixelsReadAsZeroAndAllocateNothing() {
        let r = GraphiteRaster(width: 300, height: 200)
        #expect(r.value(x: 10, y: 10) == 0)
        #expect(r.value(x: -1, y: 500) == 0)
        #expect(r.isEmpty)
    }

    @Test func writesLandInTheRightTile() {
        var r = GraphiteRaster(width: 300, height: 200)
        let coord = TileCoord(x: 1, y: 1)
        r.withMutableTile(coord) { $0[3 * GraphiteRaster.tileSize + 5] = 0.75 }
        #expect(r.value(x: 128 + 5, y: 128 + 3) == 0.75)
        #expect(r.tiles.count == 1)
    }

    @Test func edgeTilesAreClipped() {
        let r = GraphiteRaster(width: 300, height: 200)
        #expect(r.rect(of: TileCoord(x: 2, y: 1)) == PixelRect(minX: 256, minY: 128, maxX: 300, maxY: 200))
    }

    @Test func findsTilesUnderARect() {
        let r = GraphiteRaster(width: 300, height: 200)
        let coords = r.tileCoords(overlapping: PixelRect(minX: 120, minY: 10, maxX: 260, maxY: 20))
        #expect(Set(coords) == [TileCoord(x: 0, y: 0), TileCoord(x: 1, y: 0), TileCoord(x: 2, y: 0)])
        #expect(r.tileCoords(overlapping: PixelRect(minX: 400, minY: 0, maxX: 500, maxY: 10)).isEmpty)
    }

    @Test func aKeptTileIsUnaffectedByLaterWrites() {
        var r = GraphiteRaster(width: 128, height: 128)
        let coord = TileCoord(x: 0, y: 0)
        r.withMutableTile(coord) { $0[0] = 0.25 }
        let kept = r.tile(coord)
        r.withMutableTile(coord) { $0[0] = 0.9 }
        #expect(kept?[0] == 0.25)
        #expect(r.value(x: 0, y: 0) == 0.9)
    }
}

struct DabRasterizerTests {
    static let paper = PaperTexture(size: 64, seed: 1)
    /// Paper whose every point is a peak, so grain never hides graphite.
    static let flatPaper = PaperTexture(flatAt: 1, size: 64)

    func shape(radius: Double = 4, opacity: Double = 0.5, threshold: Double = 0.3) -> DabShape {
        DabShape(radiusAlong: radius, radiusAcross: radius, angle: 0, opacity: opacity,
                 grainThreshold: threshold, edgeSoftness: 0.3)
    }

    @Test func coversTheInsideAndNotTheOutside() {
        var r = GraphiteRaster(width: 64, height: 64)
        DabRasterizer.stamp(center: CGPoint(x: 32, y: 32), shape: shape(), into: &r, paper: Self.flatPaper, seed: 1)
        #expect(r.value(x: 32, y: 32) > 0.4)
        #expect(r.value(x: 32, y: 32) <= 0.5)
        #expect(r.value(x: 40, y: 32) == 0)
        #expect(r.value(x: 32, y: 24) == 0)
    }

    @Test func overlappingDabsInOneStrokeDoNotPileUp() {
        var once = GraphiteRaster(width: 64, height: 64)
        var twice = GraphiteRaster(width: 64, height: 64)
        let center = CGPoint(x: 20.3, y: 20.7)
        DabRasterizer.stamp(center: center, shape: shape(), into: &once, paper: Self.paper, seed: 9)
        DabRasterizer.stamp(center: center, shape: shape(), into: &twice, paper: Self.paper, seed: 9)
        DabRasterizer.stamp(center: center, shape: shape(), into: &twice, paper: Self.paper, seed: 9)
        #expect(once.tiles == twice.tiles)
    }

    /// Mean deposit on the paper's peaks and in its valleys under one big dab.
    func peaksAndValleys(grainSoftness: Double) -> (peaks: Float, valleys: Float) {
        var r = GraphiteRaster(width: 64, height: 64)
        var s = shape(radius: 30, threshold: 0.5)
        s.grainSoftness = grainSoftness
        DabRasterizer.stamp(center: CGPoint(x: 32, y: 32), shape: s, into: &r, paper: Self.paper, seed: 1)
        var high: [Float] = [], low: [Float] = []
        for y in 20..<44 { for x in 20..<44 {
            let h = Self.paper.height(x: x, y: y)
            if h > 0.9 { high.append(r.value(x: x, y: y)) }
            if h < 0.1 { low.append(r.value(x: x, y: y)) }
        } }
        return (high.reduce(0, +) / Float(max(high.count, 1)), low.reduce(0, +) / Float(max(low.count, 1)))
    }

    @Test func peaksCatchGraphiteValleysDoNot() {
        let sharp = peaksAndValleys(grainSoftness: 0.2)
        #expect(sharp.peaks > 0.35)
        #expect(sharp.valleys == 0)
    }

    @Test func aGentlerGrainStepLetsSomeGraphiteIntoTheValleys() {
        let gentle = peaksAndValleys(grainSoftness: 0.6)
        #expect(gentle.valleys > 0)
        #expect(gentle.valleys < gentle.peaks)
    }

    @Test func tiltedPatchStretchesAlongItsAngle() {
        var r = GraphiteRaster(width: 64, height: 64)
        let tilted = DabShape(radiusAlong: 20, radiusAcross: 4, angle: .pi / 2, opacity: 0.5,
                              grainThreshold: 0, edgeSoftness: 0.2)
        DabRasterizer.stamp(center: CGPoint(x: 32, y: 32), shape: tilted, into: &r, paper: Self.flatPaper, seed: 1)
        #expect(r.value(x: 32, y: 48) > 0, "reaches far along y")
        #expect(r.value(x: 40, y: 32) == 0, "stays narrow along x")
    }

    @Test func dabsOffTheSheetAreIgnored() {
        var r = GraphiteRaster(width: 64, height: 64)
        let dirty = DabRasterizer.stamp(center: CGPoint(x: -100, y: 30), shape: shape(), into: &r, paper: Self.paper, seed: 1)
        #expect(dirty.isEmpty)
        #expect(r.isEmpty)
        let partly = DabRasterizer.stamp(center: CGPoint(x: 1, y: 1), shape: shape(), into: &r, paper: Self.flatPaper, seed: 1)
        #expect(partly.minX == 0 && partly.minY == 0)
        #expect(r.value(x: 0, y: 0) > 0)
    }

    @Test func tinyDabsStillShow() {
        var r = GraphiteRaster(width: 16, height: 16)
        let tiny = DabShape(radiusAlong: 0.6, radiusAcross: 0.6, angle: 0, opacity: 0.5, grainThreshold: 0, edgeSoftness: 0.3)
        DabRasterizer.stamp(center: CGPoint(x: 8.5, y: 8.5), shape: tiny, into: &r, paper: Self.flatPaper, seed: 1)
        #expect(r.value(x: 8, y: 8) > 0.2)
    }
}

struct GraphiteMathTests {
    @Test func goingOverALineDarkensItTowardTheLeadsLimit() {
        var d: Float = 0
        var history: [Float] = []
        for _ in 0..<12 {
            d = GraphiteMath.composite(base: d, stroke: 0.5, maxDensity: 0.7)
            history.append(d)
        }
        #expect(abs(history[0] - 0.35) < 1e-6)
        for (a, b) in zip(history, history.dropFirst()) {
            #expect(b > a)
            #expect(b - a < 0.35)
        }
        #expect(history.last! <= 0.7)
        #expect(history.last! > 0.69)
    }

    @Test func aHardLeadCannotLightenWhatASoftOneLaid() {
        let dark = GraphiteMath.composite(base: 0, stroke: 1, maxDensity: 0.93)
        #expect(GraphiteMath.composite(base: dark, stroke: 1, maxDensity: 0.6) == dark)
    }

    @Test func nothingLaidChangesNothing() {
        #expect(GraphiteMath.composite(base: 0.4, stroke: 0, maxDensity: 0.9) == 0.4)
    }
}
