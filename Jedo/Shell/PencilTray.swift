import SwiftUI

/// The grade in hand: a row of grades, each with a swatch as dark as one
/// ordinary stroke of that lead. It sits first in the hand group.
struct PencilGrades: View {
    @Binding var selection: PencilGrade

    var body: some View {
        HStack(spacing: Metric.cellGap) {
            ForEach(PencilGrade.allCases) { grade in
                let selected = grade == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = grade }
                } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(Color(white: 0.96 - 0.91 * grade.parameters.maxDensity * grade.parameters.passOpacity))
                            .overlay(Circle().strokeBorder(Palette.ink.opacity(0.15), lineWidth: 0.5))
                            .frame(width: 12, height: 12)
                        Text(grade.label)
                            .font(.system(size: 13, weight: selected ? .bold : .medium, design: .rounded))
                    }
                    .frame(width: 38, height: Metric.cell)
                    .foregroundStyle(selected ? Color.white : Palette.ink.opacity(0.8))
                    .background(selected ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: Metric.cellRadius))
                    .contentShape(RoundedRectangle(cornerRadius: Metric.cellRadius))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("연필 \(grade.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

#Preview {
    @Previewable @State var grade = PencilGrade.b2
    ControlGroup { PencilGrades(selection: $grade) }
        .padding()
}
