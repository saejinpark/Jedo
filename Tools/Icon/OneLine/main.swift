// One idea: a tool, and the line the hand draws along it.
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
let args = CommandLine.arguments
let from = args.count > 2 ? Double(args[2])! : 120.0
let turn = args.count > 3 ? Double(args[3])! : 0.0

let ground = CGGradient(colorsSpace: space, colors: [hex(0x34436B), hex(0x161B2C)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(ground, start: .zero, end: CGPoint(x: 0, y: size), options: [])

let outline = FrenchCurveData.smallOutline, cutout = FrenchCurveData.smallCutout
let xs = outline.map(\.0), ys = outline.map(\.1)
let scale = 740 / (ys.max()! - ys.min()!)
let mid = (x: (xs.max()! + xs.min()!) / 2, y: (ys.max()! + ys.min()!) / 2)
func place(_ p: (Double, Double)) -> CGPoint {
    let x = (p.0 - mid.x) * scale, y = (p.1 - mid.y) * scale
    return CGPoint(x: 540 + x * cos(turn) - y * sin(turn), y: 512 + x * sin(turn) + y * cos(turn))
}
let pts = outline.map(place)

// The line: a stretch of the curve's own edge, a pencil's width outside it, running on past the tool.
var area = 0.0
for i in pts.indices { let a = pts[i], b = pts[(i + 1) % pts.count]; area += Double(a.x * b.y - b.x * a.y) }
let sign = area > 0 ? 1.0 : -1.0
var lengths = [0.0]
for i in pts.indices { let a = pts[i], b = pts[(i + 1) % pts.count]; lengths.append(lengths.last! + hypot(Double(b.x - a.x), Double(b.y - a.y))) }
let total = lengths.last!
func edge(_ s: Double, out: Double) -> CGPoint {
    let d = (s.truncatingRemainder(dividingBy: total) + total).truncatingRemainder(dividingBy: total)
    let i = max(lengths.firstIndex { $0 > d }! - 1, 0)
    let a = pts[i], b = pts[(i + 1) % pts.count], t = (d - lengths[i]) / max(lengths[i + 1] - lengths[i], 1e-9)
    let dx = Double(b.x - a.x), dy = Double(b.y - a.y), l = max(hypot(dx, dy), 1e-9)
    return CGPoint(x: Double(a.x) + dx * t + sign * dy / l * out, y: Double(a.y) + dy * t - sign * dx / l * out)
}
// The long smooth side that faces left: the longest run of the edge whose outside is to the left.
let n = 600
let facesLeft = (0..<n).map { k -> Bool in
    let s = Double(k) / Double(n) * total
    let on = edge(s, out: 0), off = edge(s, out: 10)
    return Double(off.x - on.x) < -3.5
}
var best = (start: 0, count: 0), run = 0
for k in 0..<(2 * n) {
    run = facesLeft[k % n] ? run + 1 : 0
    if run > best.count, run <= n { best = (k - run + 1, run) }
}
var s0 = Double(best.start) / Double(n) * total, s1 = Double(best.start + best.count) / Double(n) * total
// Drawn from the top down, so the hand runs off the tool at the bottom.
if edge(s0, out: 0).y > edge(s1, out: 0).y { swap(&s0, &s1) }
let trim = (s1 - s0) * 0.03
s0 += trim; s1 -= trim
let line = CGMutablePath()
let steps = 300
for k in 0...steps {
    let p = edge(s0 + (s1 - s0) * Double(k) / Double(steps), out: 34)
    if k == 0 { line.move(to: p) } else { line.addLine(to: p) }
}
let last = edge(s1, out: 34), before = edge(s1 - (s1 - s0) * 0.02, out: 34)
let tl = max(hypot(Double(last.x - before.x), Double(last.y - before.y)), 1e-9)
let carry = from
line.addLine(to: CGPoint(x: Double(last.x) + Double(last.x - before.x) / tl * carry, y: Double(last.y) + Double(last.y - before.y) / tl * carry))
ctx.addPath(line)
ctx.setStrokeColor(hex(0xF7F4EC)); ctx.setLineWidth(30); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.strokePath()

// The tool: old orange plastic.
let path = CGMutablePath()
path.addLines(between: pts); path.closeSubpath()
path.addLines(between: cutout.map(place)); path.closeSubpath()
ctx.saveGState(); ctx.translateBy(x: 0, y: 16); ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 0.25)); ctx.fillPath(using: .evenOdd); ctx.restoreGState()
ctx.saveGState()
ctx.addPath(path); ctx.clip(using: .evenOdd)
let plastic = CGGradient(colorsSpace: space, colors: [hex(0xFFC79A), hex(0xF79A58), hex(0xE9803F)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(plastic, start: CGPoint(x: 360, y: 160), end: CGPoint(x: 660, y: 880), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
