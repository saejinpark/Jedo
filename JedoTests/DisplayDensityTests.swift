import Testing
@testable import Jedo

struct DisplayDensityTests {
    @Test(arguments: [
        (2266.0, 326.0), // iPad mini (6th gen, A17 Pro)
        (2360.0, 264.0), // iPad (10th gen)
        (2420.0, 264.0), // iPad Pro 11-inch (M4)
        (2732.0, 264.0), // iPad Air 13-inch
        (2752.0, 264.0), // iPad Pro 13-inch (M4)
    ])
    func recognisesThePanel(longSide: Double, ppi: Double) {
        #expect(DisplayDensity.pixelsPerInch(nativeLongSidePixels: longSide) == ppi)
    }

    @Test func millimetresFollowFromPPI() {
        #expect(abs(DisplayDensity.pixelsPerMillimeter(nativeLongSidePixels: 2752) - 10.394) < 0.001)
    }
}
