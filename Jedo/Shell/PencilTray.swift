import SwiftUI

/// Seven pencils standing in a tray. The one in hand is lifted.
struct PencilTray: View {
    @Binding var selection: PencilGrade

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(PencilGrade.allCases) { grade in
                    Button {
                        withAnimation(.spring(duration: 0.28, bounce: 0.35)) { selection = grade }
                    } label: {
                        PencilGlyph(grade: grade)
                            .offset(y: grade == selection ? -22 : 0)
                            .shadow(color: .black.opacity(grade == selection ? 0.22 : 0.08),
                                    radius: grade == selection ? 6 : 2, y: grade == selection ? 5 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("연필 \(grade.label)")
                    .accessibilityAddTraits(grade == selection ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            // The front lip of the tray hides the pencils' ends.
            TrayLip(selection: selection)
        }
        .fixedSize()
    }
}

private struct TrayLip: View {
    let selection: PencilGrade

    var body: some View {
        HStack {
            Text(selection.label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Spacer()
            Text("연필")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink.opacity(0.5))
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 18)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 18,
                                                                  bottomTrailingRadius: 18, topTrailingRadius: 10))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 18,
                                        bottomTrailingRadius: 18, topTrailingRadius: 10)
            .strokeBorder(Palette.ink.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .accessibilityHidden(true)
    }
}

/// A sharpened drafting pencil, point up. The tip shows how dark the lead is.
struct PencilGlyph: View {
    let grade: PencilGrade

    static let width: CGFloat = 28
    static let coneHeight: CGFloat = 30
    static let bodyHeight: CGFloat = 78

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Cone()
                    .fill(LinearGradient(colors: [Palette.woodShade, Palette.wood, Palette.wood, Palette.woodShade],
                                         startPoint: .leading, endPoint: .trailing))
                Cone()
                    .fill(Self.leadColor(grade))
                    .frame(width: Self.width * 0.32, height: Self.coneHeight * 0.32)
            }
            .frame(width: Self.width, height: Self.coneHeight)

            ZStack(alignment: .top) {
                // Hexagonal barrel: three facets catching the light differently.
                HStack(spacing: 0) {
                    Palette.body.opacity(0.85)
                    Palette.bodyHighlight
                    Palette.body
                }
                Text(grade.label)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.label)
                    .padding(.top, 8)
            }
            .frame(width: Self.width, height: Self.bodyHeight)
        }
    }

    /// The colour the lead leaves at its darkest, over paper.
    static func leadColor(_ grade: PencilGrade) -> Color {
        let d = grade.parameters.maxDensity
        let g = GraphiteShading.graphite, p = GraphiteShading.paper
        return Color(red: g.r * d + p.r * (1 - d), green: g.g * d + p.g * (1 - d), blue: g.b * d + p.b * (1 - d))
    }
}

/// The sharpened end: a triangle pointing up.
private struct Cone: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

#Preview {
    @Previewable @State var grade = PencilGrade.b2
    PencilTray(selection: $grade)
        .padding(40)
        .background(Color(red: 0.965, green: 0.955, blue: 0.925))
}
