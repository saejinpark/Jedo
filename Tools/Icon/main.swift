// Draws the app icon: a French curve printed with screen tone, lying on a
// parallel rule, on drawing paper. The curve is the app's own outline.
// Run with Tools/Icon/render.sh

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, y down, like the paper.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
let paper = rgb(0.965, 0.953, 0.925), ink = rgb(0.11, 0.115, 0.14)

ctx.setFillColor(paper)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// The parallel rule: a clear bar across the board, graduated along its upper edge.
let rule = CGRect(x: -40, y: 660, width: size + 80, height: 150)
ctx.setFillColor(rgb(0.80, 0.82, 0.84, 0.55))
ctx.fill(rule)
ctx.setFillColor(rgb(1, 1, 1, 0.35))
ctx.fill(CGRect(x: rule.minX, y: rule.minY + 22, width: rule.width, height: 16))
ctx.setStrokeColor(ink)
ctx.setLineWidth(7)
for y in [rule.minY, rule.maxY] {
    ctx.move(to: CGPoint(x: rule.minX, y: y)); ctx.addLine(to: CGPoint(x: rule.maxX, y: y))
}
ctx.strokePath()
ctx.setLineWidth(5)
var k = 0
for x in stride(from: 46.0, to: size, by: 46.6) {
    let long = k % 5 == 0
    ctx.move(to: CGPoint(x: x, y: rule.minY)); ctx.addLine(to: CGPoint(x: x, y: rule.minY + (long ? 58 : 32)))
    k += 1
}
ctx.strokePath()

// The French curve, turned to rest on the rule.
func placed(_ raw: [(Double, Double)], _ box: CGRect, scale: Double, angle: Double, at centre: CGPoint) -> [CGPoint] {
    raw.map { p in
        let x = (p.0 - box.midX) * scale, y = (p.1 - box.midY) * scale
        return CGPoint(x: centre.x + x * cos(angle) - y * sin(angle), y: centre.y + x * sin(angle) + y * cos(angle))
    }
}
let outline = FrenchCurveData.largeOutline, cutout = FrenchCurveData.largeCutout
let xs = outline.map(\.0), ys = outline.map(\.1)
let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
let angle = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : -0.5
let scale = 930 / max(box.width, box.height)
let centre = CGPoint(x: 500, y: 452)
let path = CGMutablePath()
path.addLines(between: placed(outline, box, scale: scale, angle: angle, at: centre)); path.closeSubpath()
path.addLines(between: placed(cutout, box, scale: scale, angle: angle, at: centre)); path.closeSubpath()

ctx.saveGState()
ctx.addPath(path)
ctx.clip(using: .evenOdd)
ctx.setFillColor(rgb(0.985, 0.98, 0.965))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
// Screen tone: dots on a grid turned 45 degrees, growing from light to dark across the curve.
let pitch = 30.0
ctx.setFillColor(ink)
for i in -50...50 {
    for j in -50...50 {
        let u = Double(i) * pitch, v = Double(j) * pitch
        let x = 512 + (u - v) * 0.7071, y = 512 + (u + v) * 0.7071
        guard x > -pitch, y > -pitch, x < size + pitch, y < size + pitch else { continue }
        // Dark where it rests on the rule, fading to almost nothing at its tip.
        let t = min(max((y - 90) / 720, 0), 1)
        let coverage = 0.04 + 0.66 * t * t
        let r = pitch * (coverage / Double.pi).squareRoot()
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
}
ctx.restoreGState()
ctx.addPath(path)
ctx.setStrokeColor(ink)
ctx.setLineWidth(11)
ctx.setLineJoin(.round)
ctx.strokePath()

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
