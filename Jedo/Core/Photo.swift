import CoreGraphics
import Foundation

/// A photo laid on the desk, as a print: which picture, and how big it was printed.
struct PhotoRef: Hashable, Sendable {
    /// The picture's file name in the photo store.
    var id: String
    var widthMM: Double
    var heightMM: Double

    /// Photos come out as a 6 × 4 inch print: 152 mm on the long side.
    static let longSideMM = 152.0

    init(id: String, widthMM: Double, heightMM: Double) {
        self.id = id
        self.widthMM = widthMM
        self.heightMM = heightMM
    }

    /// A print of a picture `width` by `height` pixels.
    init(id: String, pixelWidth width: Int, pixelHeight height: Int) {
        let long = Double(max(width, height, 1))
        self.init(id: id, widthMM: (Self.longSideMM * Double(max(width, 1)) / long).rounded(),
                  heightMM: (Self.longSideMM * Double(max(height, 1)) / long).rounded())
    }

    var code: String { "photo.\(id).\(Int(widthMM)).\(Int(heightMM))" }

    init?(code: String) {
        let parts = code.split(separator: ".")
        guard parts.count == 4, parts[0] == "photo", let w = Double(parts[2]), let h = Double(parts[3]), w > 0, h > 0 else { return nil }
        self.init(id: String(parts[1]), widthMM: w, heightMM: h)
    }
}

/// A picture's pixels, for taking colour from: RGBA, 8 bits each, row by row.
struct PhotoPixels: Sendable {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    /// The colour at a point given as fractions of the picture (0…1 each way).
    func colour(u: Double, v: Double) -> (r: Double, g: Double, b: Double)? {
        guard u >= 0, u <= 1, v >= 0, v <= 1, width > 0, height > 0 else { return nil }
        let x = min(Int(u * Double(width)), width - 1), y = min(Int(v * Double(height)), height - 1)
        let i = (y * width + x) * 4
        return (Double(rgba[i]) / 255, Double(rgba[i + 1]) / 255, Double(rgba[i + 2]) / 255)
    }
}

extension CarbonPalette {
    /// Steps per channel of the colour cube a photo's colours are matched to.
    static let cubeSteps = 16
    static var firstCube: Int { firstHue + hueSteps }

    /// The palette entry nearest a colour.
    static func cubeIndex(_ c: (r: Double, g: Double, b: Double)) -> Int {
        let n = cubeSteps - 1
        func q(_ v: Double) -> Int { min(max(Int((v * Double(n)).rounded()), 0), n) }
        return firstCube + (q(c.r) * cubeSteps + q(c.g)) * cubeSteps + q(c.b)
    }

    static let cube: [(r: Double, g: Double, b: Double)] = {
        let n = Double(cubeSteps - 1)
        var out: [(r: Double, g: Double, b: Double)] = []
        for r in 0..<cubeSteps { for g in 0..<cubeSteps { for b in 0..<cubeSteps { out.append((Double(r) / n, Double(g) / n, Double(b) / n)) } } }
        return out
    }()
}
