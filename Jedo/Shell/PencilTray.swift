import SwiftUI

/// The grade in hand: a row of grades, each with a swatch as dark as one
/// ordinary stroke of that lead. Nothing else, so it stays out of the way.
struct PencilTray: View {
    @Binding var selection: PencilGrade

    var body: some View {
        HStack(spacing: 2) {
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
                    .frame(width: 40, height: 48)
                    .foregroundStyle(selected ? Color.white : Palette.ink.opacity(0.8))
                    .background(selected ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("연필 \(grade.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.ink.opacity(0.08)))
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        .fixedSize()
    }
}

#Preview {
    @Previewable @State var grade = PencilGrade.b2
    PencilTray(selection: $grade)
        .padding()
}
