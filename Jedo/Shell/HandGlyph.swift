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
                // An art knife: a slim body, and a narrow 30° blade coming out of it to a sharp point.
                context.translateBy(x: 23, y: 23)
                context.rotate(by: .degrees(-135))
                context.stroke(Path(roundedRect: CGRect(x: 0, y: -2.6, width: 18, height: 5.2), cornerRadius: 1.8),
                               with: .foreground, style: line)
                var blade = Path()
                blade.move(to: CGPoint(x: 18, y: -1.6))
                blade.addLine(to: CGPoint(x: 29.5, y: -1.6))
                blade.addLine(to: CGPoint(x: 24, y: 1.6))
                blade.addLine(to: CGPoint(x: 18, y: 1.6))
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
                // An embossing stylus: a handle in the middle, a thin steel neck at each end, a ball on each, one larger.
                context.translateBy(x: 13, y: 13)
                context.rotate(by: .degrees(-45))
                context.fill(Path(roundedRect: CGRect(x: -6.5, y: -2, width: 13, height: 4), cornerRadius: 2), with: .foreground)
                var necks = Path()
                necks.move(to: CGPoint(x: -6.5, y: 0)); necks.addLine(to: CGPoint(x: -14, y: 0))
                necks.move(to: CGPoint(x: 6.5, y: 0)); necks.addLine(to: CGPoint(x: 13.5, y: 0))
                context.stroke(necks, with: .foreground, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: -16.6, y: -2, width: 4, height: 4)), with: .foreground)
                context.fill(Path(ellipseIn: CGRect(x: 12.8, y: -1.4, width: 2.8, height: 2.8)), with: .foreground)
            }
        }
    }
}
