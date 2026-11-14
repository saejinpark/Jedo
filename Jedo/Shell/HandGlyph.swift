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
                // A plain body and its slanted blade, lying from bottom left to top right.
                context.translateBy(x: 3.5, y: 22.5)
                context.rotate(by: .degrees(-45))
                context.stroke(Path(roundedRect: CGRect(x: 0, y: -3, width: 17, height: 6), cornerRadius: 1.5), with: .foreground, style: line)
                var blade = Path()
                blade.move(to: CGPoint(x: 17, y: -2))
                blade.addLine(to: CGPoint(x: 23, y: -2))
                blade.addLine(to: CGPoint(x: 26.5, y: 2))
                blade.addLine(to: CGPoint(x: 17, y: 2))
                blade.closeSubpath()
                context.fill(blade, with: .foreground)
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
                // A slim rod with a ball at its point.
                var rod = Path()
                rod.move(to: CGPoint(x: 4, y: 22))
                rod.addLine(to: CGPoint(x: 19.5, y: 6.5))
                context.stroke(rod, with: .foreground, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: 18.5, y: 2.5, width: 5, height: 5)), with: .foreground)
            }
        }
    }
}
