import Foundation

/// Physical size of a pixel, so a 0.5 mm lead draws 0.5 mm on any iPad.
enum DisplayDensity {
    /// iPad mini panels are 326 ppi; every other current iPad is 264 ppi.
    /// iPadOS does not report ppi, so the panel is recognised by its pixel size.
    static func pixelsPerInch(nativeLongSidePixels: Double) -> Double {
        nativeLongSidePixels <= 2266 ? 326 : 264
    }

    static func pixelsPerMillimeter(nativeLongSidePixels: Double) -> Double {
        pixelsPerInch(nativeLongSidePixels: nativeLongSidePixels) / 25.4
    }
}
