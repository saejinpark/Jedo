import Testing
@testable import Jedo

struct PaperTextureTests {
    // Built once: generating paper is the slowest thing in the suite.
    static let paper = PaperTexture(size: 256, seed: 42)

    @Test func isDeterministicForASeed() {
        let again = PaperTexture(size: 256, seed: 42)
        #expect(again.heights == Self.paper.heights)
    }

    @Test func differentSeedsGiveDifferentPaper() {
        #expect(PaperTexture(size: 256, seed: 43).heights != Self.paper.heights)
    }

    @Test func heightsAreSpreadEvenlyOverZeroToOne() {
        let h = Self.paper.heights
        #expect(h.min() == 0)
        #expect(h.max() == 1)
        let mean = h.reduce(0, +) / Float(h.count)
        #expect(abs(mean - 0.5) < 0.01)
        // A threshold of 0.3 leaves about 30% of the surface below it.
        let below = Float(h.filter { $0 < 0.3 }.count) / Float(h.count)
        #expect(abs(below - 0.3) < 0.01)
    }

    @Test func wrapsSoItTilesSeamlessly() {
        let p = Self.paper
        for (x, y) in [(0, 0), (17, 200), (255, 3)] {
            #expect(p.height(x: x, y: y) == p.height(x: x + 256, y: y))
            #expect(p.height(x: x, y: y) == p.height(x: x, y: y - 256))
            #expect(p.height(x: x, y: y) == p.height(x: x - 512, y: y + 768))
        }
    }

    @Test func toothIsFineNotBlotchy() {
        // Neighbouring pixels are related (rounded bumps, not white noise)
        // but pixels a millimetre apart are close to independent.
        let p = Self.paper
        func correlation(_ offset: Int) -> Float {
            var sum: Float = 0
            for y in 0..<256 { for x in 0..<256 {
                sum += (p.height(x: x, y: y) - 0.5) * (p.height(x: x + offset, y: y) - 0.5)
            } }
            return sum / Float(256 * 256) / (1.0 / 12.0) // variance of uniform 0...1
        }
        #expect(correlation(1) > 0.4)
        #expect(correlation(10) < 0.3)
    }

    @Test func seamBetweenRepeatsLooksLikeAnyOtherColumn() {
        // The jump across the wrap should be no bigger than an ordinary neighbour step.
        let p = Self.paper
        func meanStep(at x: Int) -> Float {
            (0..<256).reduce(0) { $0 + abs(p.height(x: x, y: $1) - p.height(x: x + 1, y: $1)) } / 256
        }
        let ordinary = (0..<250).map(meanStep(at:)).reduce(0, +) / 250
        #expect(meanStep(at: 255) < ordinary * 1.5)
    }
}

struct PixelHashTests {
    @Test func staysInUnitRangeAndVaries() {
        var values = Set<Float>()
        for x in -20..<20 { for y in -20..<20 {
            let v = pixelHash(x, y, 7)
            #expect(v >= 0 && v < 1)
            values.insert(v)
        } }
        #expect(values.count > 1500)
        #expect(pixelHash(3, 4, 1) == pixelHash(3, 4, 1))
        #expect(pixelHash(3, 4, 1) != pixelHash(3, 4, 2))
    }
}
