import CoreGraphics
import Testing
@testable import Jedo

struct DabSpacerTests {
    func sample(_ x: Double, _ y: Double = 0, pressure: Double = 0.5) -> StrokeSample {
        StrokeSample(location: CGPoint(x: x, y: y), pressure: pressure)
    }

    @Test func firstTouchLeavesADot() {
        var spacer = DabSpacer()
        let dabs = spacer.append(sample(5, 5), spacing: { _ in 2 })
        #expect(dabs.map(\.location) == [CGPoint(x: 5, y: 5)])
    }

    @Test func dabsAreEvenlySpacedAlongALine() {
        var spacer = DabSpacer()
        var dabs = spacer.append(sample(0), spacing: { _ in 2 })
        dabs += spacer.append(sample(10), spacing: { _ in 2 })
        #expect(dabs.map(\.location.x) == [0, 2, 4, 6, 8, 10])
    }

    @Test func spacingCarriesAcrossBatches() {
        let path = stride(from: 0.0, through: 30, by: 0.7).map { sample($0, $0 * 0.5) } + [sample(30, 15)]
        var oneGo = DabSpacer()
        var whole: [StrokeSample] = []
        for s in path { whole += oneGo.append(s, spacing: { _ in 1.5 }) }

        let fine = (0..<300).map { sample(Double($0) * 0.1, Double($0) * 0.05) } + [sample(30, 15)]
        var fineSpacer = DabSpacer()
        var fromFine: [StrokeSample] = []
        for s in fine { fromFine += fineSpacer.append(s, spacing: { _ in 1.5 }) }

        // Same path sampled differently gives the same dabs.
        #expect(whole.count == fromFine.count)
        for (a, b) in zip(whole, fromFine) {
            #expect(abs(a.location.x - b.location.x) < 1e-6)
            #expect(abs(a.location.y - b.location.y) < 1e-6)
        }
        for (a, b) in zip(whole, whole.dropFirst()) {
            #expect(abs(hypot(b.location.x - a.location.x, b.location.y - a.location.y) - 1.5) < 1e-6)
        }
    }

    @Test func holdingStillAddsNothing() {
        var spacer = DabSpacer()
        _ = spacer.append(sample(3), spacing: { _ in 1 })
        #expect(spacer.append(sample(3), spacing: { _ in 1 }).isEmpty)
        #expect(spacer.append(sample(3), spacing: { _ in 1 }).isEmpty)
    }

    @Test func pressureIsInterpolatedBetweenSamples() {
        var spacer = DabSpacer()
        _ = spacer.append(sample(0, pressure: 0), spacing: { _ in 5 })
        let dabs = spacer.append(sample(10, pressure: 1), spacing: { _ in 5 })
        #expect(dabs.count == 2)
        #expect(abs(dabs[0].pressure - 0.5) < 1e-9)
        #expect(abs(dabs[1].pressure - 1) < 1e-9)
    }

    @Test func aCopyCanRunAheadWithoutDisturbingTheStroke() {
        var spacer = DabSpacer()
        _ = spacer.append(sample(0), spacing: { _ in 1 })
        var lookahead = spacer
        _ = lookahead.append(sample(7.5), spacing: { _ in 1 })
        let real = spacer.append(sample(3), spacing: { _ in 1 })
        #expect(real.map(\.location.x) == [1, 2, 3])
    }

    @Test func nonsenseSpacingCannotHang() {
        var spacer = DabSpacer()
        _ = spacer.append(sample(0), spacing: { _ in 0 })
        let dabs = spacer.append(sample(10), spacing: { _ in .nan })
        #expect(dabs.count <= 101)
    }

    @Test func azimuthTakesTheShortWayRound() {
        let a = StrokeSample(location: .zero, azimuth: 3.0)
        let b = StrokeSample(location: .zero, azimuth: -3.0)
        let mid = StrokeSample.interpolate(a, b, 0.5).azimuth
        #expect(abs(abs(mid) - .pi) < 0.01)
    }
}
