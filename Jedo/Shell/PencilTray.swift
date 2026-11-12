import SwiftUI

/// The grade in hand: a row of grades, each with a swatch as dark as one
/// ordinary stroke of that lead. It sits first in the hand group.
struct PencilGrades: View {
    @Binding var selection: PencilGrade
    /// How worn each point is, shown as the width of the line it now draws.
    var wear: [PencilGrade: Double] = [:]
    /// Tapping the grade already in hand sharpens it.
    var sharpen: (PencilGrade) -> Void = { _ in }

    var body: some View {
        HStack(spacing: Metric.cellGap) {
            ForEach(PencilGrade.allCases) { grade in
                let selected = grade == selection
                Button {
                    if selection == grade { sharpen(grade) } else {
                        withAnimation(.snappy(duration: 0.2)) { selection = grade }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Circle()
                            .fill(Color(white: 0.96 - 0.91 * grade.parameters.maxDensity * grade.parameters.passOpacity))
                            .overlay(Circle().strokeBorder(Palette.ink.opacity(0.15), lineWidth: 0.5))
                            .frame(width: 12, height: 12)
                        Text(grade.label)
                            .font(.system(size: 13, weight: selected ? .bold : .medium, design: .rounded))
                        LeadTip(wear: wear[grade] ?? 0)
                            .frame(width: 18, height: 5)
                    }
                    .frame(width: 38, height: Metric.cell)
                    .foregroundStyle(selected ? Color.white : Palette.ink.opacity(0.8))
                    .background(selected ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: Metric.cellRadius))
                    .contentShape(RoundedRectangle(cornerRadius: Metric.cellRadius))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("연필 \(grade.label)")
                .accessibilityHint(selection == grade ? "한 번 더 누르면 깎습니다" : "")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// The line the pencil draws now: a hairline when freshly sharpened,
/// widening as the point wears, drawn to the same proportion as on paper.
struct LeadTip: View {
    var wear: Double

    var body: some View {
        let w = min(max(wear, 0), 1)
        Capsule()
            .frame(height: 1 + PencilDynamics.bluntWidening * 1.3 * w)
            .frame(maxHeight: .infinity)
            .opacity(0.5 + 0.4 * w)
            .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State var grade = PencilGrade.b2
    ControlGroup { PencilGrades(selection: $grade) }
        .padding()
}
