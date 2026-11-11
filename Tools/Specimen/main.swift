// Renders specimen sheets of every pencil grade with the app's own Core code,
// so the graphite look can be judged and tuned on a Mac.
// Run with Tools/Specimen/render.sh

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let pixelsPerMM = 264.0 / 25.4 // iPad Pro / Air at 264 ppi
let rowHeight = 210
let width = 1800
let height = rowHeight * PencilGrade.allCases.count + 40
let sheet = DraftingSheet(width: width, height: height, pixelsPerMillimeter: pixelsPerMM)

/// Feeds a path to the sheet the way touches arrive: a sample every few pixels.
func draw(_ grade: PencilGrade, points: [CGPoint], pressure: (Double) -> Double,
          altitude: Double = 55 * .pi / 180, azimuth: Double = -2.4, step: Double = 4) {
    var samples: [StrokeSample] = []
    for i in 0..<(points.count - 1) {
        let a = points[i], b = points[i + 1]
        let n = max(Int((hypot(b.x - a.x, b.y - a.y) / step).rounded(.up)), 1)
        for k in 0..<n {
            let t = Double(k) / Double(n)
            samples.append(StrokeSample(location: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                                        pressure: 0, altitude: altitude, azimuth: azimuth))
        }
    }
    samples.append(StrokeSample(location: points.last!, altitude: altitude, azimuth: azimuth))
    for i in samples.indices { samples[i].pressure = pressure(Double(i) / Double(max(samples.count - 1, 1))) }
    sheet.beginStroke(grade: grade, at: samples[0])
    sheet.extendStroke(with: Array(samples.dropFirst()), predicted: [])
    sheet.endStroke()
}

for grade in PencilGrade.allCases {
    let top = Double(40 + grade.rawValue * rowHeight)

    // 1. Pressure ramp, light to hard, with a gentle wave.
    let ramp = stride(from: 0.0, through: 1.0, by: 0.02).map {
        CGPoint(x: 90 + 480 * $0, y: top + 45 + 10 * sin($0 * 9))
    }
    draw(grade, points: ramp, pressure: { 0.03 + 0.97 * $0 })

    // 2. Medium pressure line, then one, two and three passes over the same short line.
    draw(grade, points: [CGPoint(x: 90, y: top + 100), CGPoint(x: 570, y: top + 100)], pressure: { _ in 0.45 })
    for passes in 1...3 {
        let x0 = 90.0 + Double(passes - 1) * 165
        for p in 0..<passes {
            let j = Double(p) * 0.4
            draw(grade, points: [CGPoint(x: x0, y: top + 150 + j), CGPoint(x: x0 + 140, y: top + 150 - j)],
                 pressure: { _ in 0.4 })
        }
    }

    // 3. Shading with the lead on its side: zigzag back and forth.
    var zig: [CGPoint] = []
    for i in 0...14 {
        let x = 640.0 + Double(i) * 22
        zig.append(CGPoint(x: x, y: top + (i.isMultiple(of: 2) ? 25 : 175)))
    }
    draw(grade, points: zig, pressure: { _ in 0.35 }, altitude: 18 * .pi / 180, azimuth: .pi * 0.9)

    // 4. Light hatching, then cross-hatching at medium pressure.
    for i in 0..<24 {
        let x = 1020.0 + Double(i) * 7
        draw(grade, points: [CGPoint(x: x, y: top + 175), CGPoint(x: x + 70, y: top + 25)], pressure: { _ in 0.25 })
    }
    for i in 0..<24 {
        let x = 1240.0 + Double(i) * 7
        draw(grade, points: [CGPoint(x: x, y: top + 175), CGPoint(x: x + 70, y: top + 25)], pressure: { _ in 0.5 })
        draw(grade, points: [CGPoint(x: x, y: top + 25), CGPoint(x: x + 70, y: top + 175)], pressure: { _ in 0.5 })
    }

    // 5. Hard-pressed scribble patch: how dark the grade can get.
    var scribble: [CGPoint] = []
    for i in 0...30 {
        scribble.append(CGPoint(x: 1530 + Double(i % 2) * 220, y: top + 30 + Double(i) * 4.8))
    }
    draw(grade, points: scribble, pressure: { _ in 0.95 })
}

// Composite graphite over paper into an opaque image.
let paperPixels = GraphiteShading.paperPixels(sheet.paper)
var image = [UInt32](repeating: 0, count: width * height)
let tileSize = GraphiteRaster.tileSize
var tilePixels = [UInt32](repeating: 0, count: GraphiteRaster.tileArea)
for ty in 0..<((height + tileSize - 1) / tileSize) {
    for tx in 0..<((width + tileSize - 1) / tileSize) {
        let coord = TileCoord(x: tx, y: ty)
        for i in tilePixels.indices { tilePixels[i] = 0 }
        let rect = sheet.graphite.rect(of: coord)
        tilePixels.withUnsafeMutableBufferPointer { sheet.renderGraphite(tile: coord, rect: rect, into: $0) }
        for y in rect.minY..<rect.maxY {
            for x in rect.minX..<rect.maxX {
                let paper = paperPixels[(y % sheet.paper.size) * sheet.paper.size + x % sheet.paper.size]
                let g = tilePixels[(y - ty * tileSize) * tileSize + (x - tx * tileSize)]
                image[y * width + x] = GraphiteShading.composite(paper: paper, graphite: g)
            }
        }
    }
}

func write(_ pixels: [UInt32], width: Int, height: Int, to path: String, labels: Bool) {
    let space = CGColorSpaceCreateDeviceRGB()
    var copy = pixels
    let ctx = copy.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    }
    if labels {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 22, nil)
        for grade in PencilGrade.allCases {
            let attr = NSAttributedString(string: grade.label, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.7, green: 0.2, blue: 0.15, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(attr)
            ctx.textPosition = CGPoint(x: 18, y: Double(height - 40 - grade.rawValue * rowHeight - 50))
            CTLineDraw(line, ctx)
        }
    }
    let cg = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
write(image, width: width, height: height, to: outDir + "/specimen.png", labels: true)

// A 3× close-up of the 2B row, to judge grain at device-pixel scale.
let crop = (x: 60, y: 40 + 2 * rowHeight, w: 600, h: rowHeight)
let zoom = 3
var close = [UInt32](repeating: 0, count: crop.w * zoom * crop.h * zoom)
for y in 0..<(crop.h * zoom) {
    for x in 0..<(crop.w * zoom) {
        close[y * crop.w * zoom + x] = image[(crop.y + y / zoom) * width + crop.x + x / zoom]
    }
}
write(close, width: crop.w * zoom, height: crop.h * zoom, to: outDir + "/specimen-2B-close.png", labels: false)
print("wrote \(outDir)/specimen.png and specimen-2B-close.png")
