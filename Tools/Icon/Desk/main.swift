// An icon of the whole desk rather than of one tool: a sheet of drawing paper carrying the
// materials (screen tone with light scraped out of it, a skirt pressed from gingham carbon),
// and on it the tools used together (a set square riding the parallel rule, the French curve).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)
func hex(_ v: Int, _ a: Double = 1) -> CGColor { CGColor(srgbRed: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255, alpha: a) }
func poly(_ p: [CGPoint]) -> CGPath { let m = CGMutablePath(); m.addLines(between: p); m.closeSubpath(); return m }
func shadowed(_ path: CGPath, _ colour: CGColor, rule: CGPathFillRule = .winding, drop: Double = 14) {
    ctx.saveGState(); ctx.translateBy(x: 0, y: drop); ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 0.24)); ctx.fillPath(using: rule); ctx.restoreGState()
    ctx.addPath(path); ctx.setFillColor(colour); ctx.fillPath(using: rule)
}

// The desk: ink blue.
let ground = CGGradient(colorsSpace: space, colors: [hex(0x34436B), hex(0x161B2C)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(ground, start: .zero, end: CGPoint(x: 0, y: size), options: [])

// The paper, lying a little askew, and everything printed, stuck or pressed on it.
let paper = CGRect(x: 190, y: 110, width: 640, height: 790)
ctx.saveGState()
ctx.translateBy(x: 512, y: 512); ctx.rotate(by: -0.07); ctx.translateBy(x: -512, y: -512)
shadowed(CGPath(roundedRect: paper, cornerWidth: 20, cornerHeight: 20, transform: nil), hex(0xF7F4EC), drop: 18)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: paper, cornerWidth: 20, cornerHeight: 20, transform: nil)); ctx.clip()

// Screen tone over the upper right: dots on a turned grid, heavier toward the corner.
let tone = CGRect(x: 470, y: 110, width: 360, height: 350)
ctx.saveGState()
ctx.clip(to: tone)
ctx.setFillColor(hex(0x1C1E26))
let pitch = 42.0
for i in -30...30 {
    for j in -30...30 {
        let x = 650 + (Double(i) - Double(j)) * pitch * 0.7071, y = 285 + (Double(i) + Double(j)) * pitch * 0.7071
        guard tone.insetBy(dx: -pitch, dy: -pitch).contains(CGPoint(x: x, y: y)) else { continue }
        let t = min(max(((x - 470) / 360 + (460 - y) / 350) / 2, 0), 1)
        let r = pitch * ((0.16 + 0.5 * t) / Double.pi).squareRoot()
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
}
// Light scraped out of it with the blade laid flat: a soft-ended streak of bare paper.
ctx.setStrokeColor(hex(0xF7F4EC)); ctx.setLineWidth(54); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 530, y: 385)); ctx.addLine(to: CGPoint(x: 775, y: 180)); ctx.strokePath()
ctx.restoreGState()

// A skirt pressed through gingham carbon.
let skirt = CGMutablePath()
skirt.move(to: CGPoint(x: 262, y: 262)); skirt.addLine(to: CGPoint(x: 368, y: 262))
skirt.addLine(to: CGPoint(x: 436, y: 600))
skirt.addQuadCurve(to: CGPoint(x: 204, y: 600), control: CGPoint(x: 320, y: 632))
skirt.closeSubpath()
ctx.saveGState()
ctx.addPath(skirt); ctx.clip()
let cell = 39.0
for i in 0...14 {
    for j in 0...12 {
        let a = i % 2 == 0, b = j % 2 == 0
        ctx.setFillColor(a && b ? hex(0x2452B8) : a || b ? hex(0x8FB0E6) : hex(0xFFFFF0))
        ctx.fill(CGRect(x: 185 + Double(i) * cell, y: 232 + Double(j) * cell, width: cell + 0.5, height: cell + 0.5))
    }
}
ctx.restoreGState()
ctx.setFillColor(hex(0x2452B8)); ctx.fill(CGRect(x: 258, y: 238, width: 114, height: 24))
ctx.restoreGState()
ctx.restoreGState()

// The parallel rule across the desk, and a set square riding it.
let top = 742.0
let square = [CGPoint(x: 92, y: top), CGPoint(x: 412, y: top), CGPoint(x: 92, y: top - 320)]
let m = CGPoint(x: (square[0].x + square[1].x + square[2].x) / 3, y: (square[0].y + square[1].y + square[2].y) / 3)
ctx.addPath(poly(square))
ctx.addPath(poly(square.map { CGPoint(x: m.x + ($0.x - m.x) * 0.42, y: m.y + ($0.y - m.y) * 0.42) }))
ctx.setFillColor(hex(0x7FD6C2, 0.78)); ctx.fillPath(using: .evenOdd)
ctx.setFillColor(hex(0xDCE6F2, 0.62)); ctx.fill(CGRect(x: -20, y: top, width: size + 40, height: 100))
ctx.setFillColor(hex(0xFFFFFF, 0.6)); ctx.fill(CGRect(x: -20, y: top, width: size + 40, height: 14))

// In front, the French curve: old orange plastic.
let outline = FrenchCurveData.smallOutline, cutout = FrenchCurveData.smallCutout
let xs = outline.map(\.0), ys = outline.map(\.1)
let scale = 540 / (ys.max()! - ys.min()!)
let mid = (x: (xs.max()! + xs.min()!) / 2, y: (ys.max()! + ys.min()!) / 2)
let turn = 0.34
func place(_ p: (Double, Double)) -> CGPoint {
    let x = (p.0 - mid.x) * scale, y = (p.1 - mid.y) * scale
    return CGPoint(x: 668 + x * cos(turn) - y * sin(turn), y: 618 + x * sin(turn) + y * cos(turn))
}
let curve = CGMutablePath()
curve.addLines(between: outline.map(place)); curve.closeSubpath()
curve.addLines(between: cutout.map(place)); curve.closeSubpath()
ctx.saveGState(); ctx.translateBy(x: 0, y: 16); ctx.addPath(curve); ctx.setFillColor(CGColor(gray: 0, alpha: 0.26)); ctx.fillPath(using: .evenOdd); ctx.restoreGState()
ctx.saveGState()
ctx.addPath(curve); ctx.clip(using: .evenOdd)
let plastic = CGGradient(colorsSpace: space, colors: [hex(0xFFC79A, 0.97), hex(0xF79A58, 0.97), hex(0xE9803F, 0.97)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(plastic, start: CGPoint(x: 540, y: 350), end: CGPoint(x: 790, y: 890), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
