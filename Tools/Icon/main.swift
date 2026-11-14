// Draws the app icon: three tools of the drafting desk fanned from one point —
// a bamboo curve rule, a stylus, and in front a French curve (the app's own
// outline). Few filled, overlapping shapes on a plain ground, the weight in the
// middle, as the Human Interface Guidelines ask of an app icon.
// Run with Tools/Icon/render.sh

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, y down, like the paper.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func hex(_ v: Int, _ a: Double = 1) -> CGColor { rgb(Double(v >> 16 & 255) / 255, Double(v >> 8 & 255) / 255, Double(v & 255) / 255, a) }

// The ground: ink blue, lighter toward the top.
let ground = CGGradient(colorsSpace: space, colors: [hex(0x34436B), hex(0x161B2C)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(ground, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

/// A point `along` a tool from the fan's pivot and `across` it, with the tool leaning `angle` from upright.
let pivot = CGPoint(x: 512, y: 905)
func at(_ along: Double, _ across: Double, _ angle: Double) -> CGPoint {
    CGPoint(x: pivot.x + across * cos(angle) + along * sin(angle), y: pivot.y + across * sin(angle) - along * cos(angle))
}
func fill(_ points: [CGPoint], _ colour: CGColor, shadow: Bool = true) {
    let path = CGMutablePath(); path.addLines(between: points); path.closeSubpath()
    if shadow {
        ctx.saveGState(); ctx.translateBy(x: 0, y: 14); ctx.addPath(path); ctx.setFillColor(rgb(0, 0, 0, 0.22)); ctx.fillPath(); ctx.restoreGState()
    }
    ctx.addPath(path); ctx.setFillColor(colour); ctx.fillPath()
}

// 1. The bamboo curve rule, leaning left: a long band, bowed a little, with its joints and a few graduations.
do {
    let lean = -0.60, bow = { (s: Double) in 0.00016 * s * s }
    let width = { (s: Double) in 94 - 0.03 * s }
    let ss = Array(stride(from: 40.0, through: 800, by: 20))
    let band = ss.map { at($0, bow($0) - width($0) / 2, lean) } + ss.reversed().map { at($0, bow($0) + width($0) / 2, lean) }
    fill(band, hex(0xEAD9A0))
    for s in [250.0, 520.0] {
        fill([at(s, bow(s) - width(s) / 2, lean), at(s + 16, bow(s + 16) - width(s + 16) / 2, lean),
              at(s + 16, bow(s + 16) + width(s + 16) / 2, lean), at(s, bow(s) + width(s) / 2, lean)], hex(0xC2A866), shadow: false)
    }
    for s in stride(from: 110.0, through: 760, by: 65) where !(240...290).contains(s) && !(510...560).contains(s) {
        let w = width(s) / 2
        fill([at(s, bow(s) - w, lean), at(s + 11, bow(s + 11) - w, lean), at(s + 11, bow(s + 11) - w + 30, lean), at(s, bow(s) - w + 30, lean)],
             hex(0x7C6A36), shadow: false)
    }
}

// 2. The stylus, leaning right: a wooden handle, a steel shank, a ball at its tip.
do {
    let lean = 0.60
    fill([at(40, -30, lean), at(470, -30, lean), at(470, 30, lean), at(40, 30, lean)], hex(0x8E3B46))
    fill([at(470, -34, lean), at(530, -34, lean), at(530, 34, lean), at(470, 34, lean)], hex(0xF1F2F4))
    fill([at(530, -20, lean), at(770, -9, lean), at(770, 9, lean), at(530, 20, lean)], hex(0xC5CBD6))
    let tip = at(778, 0, lean)
    ctx.setFillColor(hex(0xF1F2F4))
    ctx.fillEllipse(in: CGRect(x: tip.x - 23, y: tip.y - 23, width: 46, height: 46))
}

// 3. In front, upright in the middle: the French curve.
do {
    let outline = FrenchCurveData.smallOutline
    let xs = outline.map(\.0), ys = outline.map(\.1)
    let scale = 720 / (ys.max()! - ys.min()!)
    let midX = (xs.max()! + xs.min()!) / 2
    let place = { (p: (Double, Double)) in CGPoint(x: 512 + (p.0 - midX) * scale, y: 150 + (p.1 - ys.min()!) * scale) }
    let path = CGMutablePath()
    path.addLines(between: outline.map(place)); path.closeSubpath()
    // Its inner scroll is cut clean through, so the tools behind show in it.
    path.addLines(between: FrenchCurveData.smallCutout.map(place)); path.closeSubpath()
    ctx.saveGState(); ctx.translateBy(x: 0, y: 14); ctx.addPath(path); ctx.setFillColor(rgb(0, 0, 0, 0.22)); ctx.fillPath(using: .evenOdd); ctx.restoreGState()
    // Old hard plastic: orange with a flesh tint, lighter where the light catches its upper half.
    ctx.saveGState()
    ctx.addPath(path); ctx.clip(using: .evenOdd)
    let plastic = CGGradient(colorsSpace: space, colors: [hex(0xFFC79A, 0.96), hex(0xF79A58, 0.96), hex(0xE9803F, 0.96)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(plastic, start: CGPoint(x: 380, y: 150), end: CGPoint(x: 640, y: 880), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
