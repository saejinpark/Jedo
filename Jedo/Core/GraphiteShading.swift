import Foundation

/// Colours of graphite and paper, as 32-bit little-endian BGRA
/// (`premultipliedFirst | byteOrder32Little`): the native iOS pixel layout.
enum GraphiteShading {
    /// Fully laid graphite: black with a faint cool cast.
    static let graphite: (r: Double, g: Double, b: Double) = (0.05, 0.05, 0.06)
    /// Warm white drawing paper.
    static let paper: (r: Double, g: Double, b: Double) = (0.965, 0.955, 0.925)

    static let levels = 1024

    /// Premultiplied graphite at each density step, to lay over the paper.
    static let lookup: [UInt32] = (0..<levels).map { level in
        let d = Double(level) / Double(levels - 1)
        return pack(r: graphite.r * d, g: graphite.g * d, b: graphite.b * d, a: d)
    }

    static func pack(r: Double, g: Double, b: Double, a: Double) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(min(max(v, 0), 1) * 255 + 0.5) }
        return byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    static func unpack(_ pixel: UInt32) -> (r: Double, g: Double, b: Double, a: Double) {
        (Double(pixel >> 16 & 0xFF) / 255, Double(pixel >> 8 & 0xFF) / 255,
         Double(pixel & 0xFF) / 255, Double(pixel >> 24) / 255)
    }

    /// Opaque paper pixels for one repeat of the texture. Raised tooth catches
    /// a little more light, valleys sit a little darker.
    static func paperPixels(_ texture: PaperTexture, relief paperRelief: Double = GrainStyle.default.paperRelief) -> [UInt32] {
        texture.heights.map { h in
            let shade = 1 - paperRelief / 2 + paperRelief * Double(h)
            return pack(r: paper.r * shade, g: paper.g * shade, b: paper.b * shade, a: 1)
        }
    }

    /// Graphite laid over paper, as an opaque colour. Used by tests and the specimen renderer.
    static func composite(paper paperPixel: UInt32, graphite graphitePixel: UInt32) -> UInt32 {
        let p = unpack(paperPixel), g = unpack(graphitePixel)
        return pack(r: g.r + p.r * (1 - g.a), g: g.g + p.g * (1 - g.a), b: g.b + p.b * (1 - g.a), a: 1)
    }
}
