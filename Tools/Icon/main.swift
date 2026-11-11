// Draws the app icon with the app's own graphite renderer:
// a ruled line, a compass arc and its centre mark on drawing paper.
// Run with Tools/Icon/render.sh

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
// Lines must read at 60 px, so the "millimetre" is huge here.
let sheet = DraftingSheet(width: size, height: size, pixelsPerMillimeter: 34, paper: PaperTexture(size: 256, seed: 7))

func stroke(_ grade: PencilGrade, _ points: [CGPoint], pressure: Double, step: Double = 3) {
    var samples: [StrokeSample] = []
    for (a, b) in zip(points, points.dropFirst()) {
        let n = max(Int((hypot(b.x - a.x, b.y - a.y) / step).rounded(.up)), 1)
        for k in 0..<n {
            let t = Double(k) / Double(n)
            samples.append(StrokeSample(location: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                                        pressure: pressure, altitude: 1.2, azimuth: -2.3))
        }
    }
    samples.append(StrokeSample(location: points.last!, pressure: pressure, altitude: 1.2, azimuth: -2.3))
    sheet.beginStroke(grade: grade)
    sheet.extendStroke(with: samples, predicted: [])
    sheet.endStroke()
}

// Faint construction lines in HB, gone over twice like a draftsman would.
for _ in 0..<2 {
    stroke(.hb, [CGPoint(x: 120, y: 650), CGPoint(x: 910, y: 650)], pressure: 0.35)
    stroke(.hb, [CGPoint(x: 420, y: 140), CGPoint(x: 420, y: 900)], pressure: 0.35)
}
// The compass arc in 2B, centred where the construction lines cross.
let center = CGPoint(x: 420, y: 650)
let radius = 330.0
let arc = stride(from: -1.62, through: 0.05, by: 0.01).map {
    CGPoint(x: center.x + radius * cos($0), y: center.y + radius * sin($0))
}
stroke(.b2, arc, pressure: 0.75)
stroke(.b2, arc, pressure: 0.6)
// A firm 4B object line.
stroke(.b4, [CGPoint(x: 230, y: 800), CGPoint(x: 820, y: 800)], pressure: 0.85)
// Needle mark.
stroke(.b4, [CGPoint(x: 405, y: 635), CGPoint(x: 435, y: 665)], pressure: 0.6)
stroke(.b4, [CGPoint(x: 435, y: 635), CGPoint(x: 405, y: 665)], pressure: 0.6)

let paper = GraphiteShading.paperPixels(sheet.paper)
var image = [UInt32](repeating: 0, count: size * size)
var tile = [UInt32](repeating: 0, count: GraphiteRaster.tileArea)
let n = GraphiteRaster.tileSize
for ty in 0..<(size / n) {
    for tx in 0..<(size / n) {
        let coord = TileCoord(x: tx, y: ty)
        for i in tile.indices { tile[i] = 0 }
        tile.withUnsafeMutableBufferPointer { sheet.renderGraphite(tile: coord, rect: sheet.graphite.rect(of: coord), into: $0) }
        for y in 0..<n {
            for x in 0..<n {
                let gx = tx * n + x, gy = ty * n + y
                let p = paper[(gy % sheet.paper.size) * sheet.paper.size + gx % sheet.paper.size]
                image[gy * size + gx] = GraphiteShading.composite(paper: p, graphite: tile[y * n + x])
            }
        }
    }
}

let ctx = image.withUnsafeMutableBytes {
    CGContext(data: $0.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
