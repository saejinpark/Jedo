import SwiftUI

/// Line drawings of the hand tools that have no system symbol: the snap-off
/// cutter, the brayer and the embossing stylus.
struct HandGlyph: View {
    enum Tool { case cutter, roller, stylus }
    let tool: Tool

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 26
            context.scaleBy(x: s, y: s)
            let line = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            switch tool {
            case .cutter:
                // Lying from bottom left to top right: the ribbed body, the slider, the snap-off blade.
                context.translateBy(x: 3, y: 23)
                context.rotate(by: .degrees(-45))
                var body = Path(roundedRect: CGRect(x: 0, y: -3.2, width: 19, height: 6.4), cornerRadius: 1.6)
                body.move(to: CGPoint(x: 7, y: -3.2))
                body.addLine(to: CGPoint(x: 7, y: -4.8))
                body.addLine(to: CGPoint(x: 11, y: -4.8))
                body.addLine(to: CGPoint(x: 11, y: -3.2))
                context.stroke(body, with: .foreground, style: line)
                var blade = Path()
                blade.move(to: CGPoint(x: 19, y: -2.2))
                blade.addLine(to: CGPoint(x: 26.5, y: -2.2))
                blade.addLine(to: CGPoint(x: 29.5, y: 1.6))
                blade.addLine(to: CGPoint(x: 19, y: 1.6))
                blade.closeSubpath()
                context.fill(blade, with: .foreground)
                var snaps = Path()
                for x in [21.5, 24.0] {
                    snaps.move(to: CGPoint(x: x, y: -2.2))
                    snaps.addLine(to: CGPoint(x: x + 2.4, y: 1.6))
                }
                context.stroke(snaps, with: .color(.white.opacity(0.85)), lineWidth: 0.8)
            case .roller:
                // The rubber cylinder on top, its frame, and the handle below.
                let drum = Path(roundedRect: CGRect(x: 3, y: 2.5, width: 20, height: 7), cornerRadius: 3.5)
                context.fill(drum, with: .foreground)
                var frame = Path()
                frame.move(to: CGPoint(x: 3.5, y: 6))
                frame.addLine(to: CGPoint(x: 2, y: 6))
                frame.addLine(to: CGPoint(x: 2, y: 12))
                frame.addLine(to: CGPoint(x: 13, y: 15))
                frame.move(to: CGPoint(x: 22.5, y: 6))
                frame.addLine(to: CGPoint(x: 24, y: 6))
                frame.addLine(to: CGPoint(x: 24, y: 12))
                frame.addLine(to: CGPoint(x: 13, y: 15))
                context.stroke(frame, with: .foreground, style: line)
                context.fill(Path(roundedRect: CGRect(x: 10.8, y: 15, width: 4.4, height: 9.5), cornerRadius: 2.2), with: .foreground)
            case .stylus:
                // A wooden handle, a steel shank, a ball at the tip.
                context.translateBy(x: 2.5, y: 23.5)
                context.rotate(by: .degrees(-45))
                context.stroke(Path(roundedRect: CGRect(x: 0, y: -2.2, width: 15, height: 4.4), cornerRadius: 2.2), with: .foreground, style: line)
                var shank = Path()
                shank.move(to: CGPoint(x: 15, y: 0))
                shank.addLine(to: CGPoint(x: 26, y: 0))
                context.stroke(shank, with: .foreground, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: 25.2, y: -1.8, width: 3.6, height: 3.6)), with: .foreground)
            }
        }
    }
}
