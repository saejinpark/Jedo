import SwiftUI

// The shell's design system: one way to draw a control, one way to group
// them, one set of colours and sizes. Controls sit in groups by what the
// hand does with them (`ShellLayout`). Right-handed, as standard:
//
//   필기구 (pencil hand)   lead holders, grades                    top right
//   보기·파일              edge rulers, export, arrangement, new    top right corner
//   기록 (off hand)        undo, redo                              bottom left corner
//   손                     eraser, compass, knife (with tone)      bottom left
//   종이·시트              sheets panel                            bottom left
//   책상 위 도구           rulers, set squares, templates, curves  bottom left
//
// Left-handed is the mirror; any group can be dragged to any of six places.
//
// Every control is a cell inside a group: plain when idle, filled with ink
// when it is in hand or on the desk.

/// Colours of the shell. Ink for controls; wood and enamel for drawn tool glyphs.
enum Palette {
    static let ink = Color(red: 0.16, green: 0.17, blue: 0.20)
    static let body = Color(red: 0.19, green: 0.25, blue: 0.30)
    static let bodyHighlight = Color(red: 0.31, green: 0.39, blue: 0.45)
    static let wood = Color(red: 0.89, green: 0.78, blue: 0.62)
    static let woodShade = Color(red: 0.76, green: 0.62, blue: 0.45)
    static let label = Color(red: 0.93, green: 0.88, blue: 0.74)
    /// The drawing paper, as in the picker and panels.
    static let paper = Color(red: 0.965, green: 0.955, blue: 0.925)
    /// Grid sheet rulings.
    static let ruling = Color(red: 0.20, green: 0.50, blue: 0.40)
}

/// Sizes and spacing of the shell.
enum Metric {
    /// A control cell, square.
    static let cell: CGFloat = 44
    static let cellRadius: CGFloat = 11
    /// Between cells in a group.
    static let cellGap: CGFloat = 2
    /// Around the cells, inside a group.
    static let groupInset: CGFloat = 4
    static let groupRadius: CGFloat = 15
    /// Between groups.
    static let groupGap: CGFloat = 10
    /// From the screen's edge.
    static let margin: CGFloat = 20
}

/// A group of controls on a frosted card.
struct ControlGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Metric.cellGap) { content }
            .padding(Metric.groupInset)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metric.groupRadius))
            .overlay(RoundedRectangle(cornerRadius: Metric.groupRadius).strokeBorder(Palette.ink.opacity(0.08)))
            .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
            .fixedSize()
    }
}

/// A hairline between kinds of control within one group.
struct GroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.ink.opacity(0.12))
            .frame(width: 1, height: Metric.cell - 16)
            .padding(.horizontal, 4)
    }
}

/// What a control cell shows.
enum ToolIcon {
    case symbol(String)
    case shape(ToolKind)

    init(_ kind: ToolKind) {
        self = kind == .ruler ? .symbol("ruler") : .shape(kind)
    }
}

/// The face of a control cell.
struct ToolFace: View {
    let icon: ToolIcon
    var enabled = true
    var selected = false

    var body: some View {
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name).font(.system(size: 18, weight: .semibold))
            case .shape(let kind):
                ToolGlyph(kind: kind).frame(width: 24, height: 24)
            }
        }
        .frame(width: Metric.cell, height: Metric.cell)
        .foregroundStyle(selected ? Color.white : Palette.ink.opacity(enabled ? 0.85 : 0.25))
        .background(selected ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: Metric.cellRadius))
        .contentShape(RoundedRectangle(cornerRadius: Metric.cellRadius))
    }
}

/// A control cell that does one thing.
struct ToolButton: View {
    let icon: ToolIcon
    let label: String
    var enabled = true
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolFace(icon: icon, enabled: enabled, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// A narrow control cell with a word on it, for choosing among a few kinds.
struct TextCell: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .bold : .medium, design: .rounded))
                .frame(width: 38, height: Metric.cell)
                .foregroundStyle(selected ? Color.white : Palette.ink.opacity(0.8))
                .background(selected ? AnyShapeStyle(Palette.ink.opacity(0.75)) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: Metric.cellRadius))
                .contentShape(RoundedRectangle(cornerRadius: Metric.cellRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A titled part of a panel.
struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            content
        }
        .padding(.vertical, 10)
    }
}

/// A small labelled button inside a panel, for laying a sheet on.
struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .foregroundStyle(selected ? Color.white : Palette.ink)
                .background(selected ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.ink.opacity(0.06)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
