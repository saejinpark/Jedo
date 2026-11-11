import CoreGraphics
import Testing
@testable import Jedo

struct QuarterTurnsTests {
    @Test func normalisesIntoZeroToThree() {
        #expect(QuarterTurns(5).count == 1)
        #expect(QuarterTurns(-1).count == 3)
        #expect(QuarterTurns(-8).count == 0)
    }

    @Test(arguments: [0, 1, 2, 3])
    func recognisesUIKitRotations(turns: Int) {
        let rotation = CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2)
        #expect(QuarterTurns(approximating: rotation).count == turns)
        #expect(QuarterTurns(approximating: rotation.inverted()).count == (4 - turns) % 4)
    }

    @Test(arguments: [0, 1, 2, 3])
    func exactTransformMatchesTheRotation(turns: Int) {
        let exact = QuarterTurns(turns).transform
        let rotation = CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2)
        for value in [exact.a, exact.b, exact.c, exact.d] {
            #expect([-1, 0, 1].contains(value), "no rounding residue")
        }
        #expect(abs(exact.a - rotation.a) < 1e-9 && abs(exact.b - rotation.b) < 1e-9)
        #expect(abs(exact.c - rotation.c) < 1e-9 && abs(exact.d - rotation.d) < 1e-9)
    }

    @Test func turningBackUndoesATurn() {
        // The canvas turns against the interface, so the paper stays put.
        var canvas = QuarterTurns(0)
        for interfaceTurn in [1, 1, 3, 2, 1] {
            canvas = canvas + -QuarterTurns(interfaceTurn)
        }
        #expect(canvas == QuarterTurns(-8))
        #expect(QuarterTurns(1) + -QuarterTurns(1) == QuarterTurns(0))
    }

    @Test func toleratesNearlyExactInput() {
        let wobbly = CGAffineTransform(a: 1e-12, b: 0.9999999, c: -1, d: 2e-12, tx: 0, ty: 0)
        #expect(QuarterTurns(approximating: wobbly).count == 1)
    }
}
