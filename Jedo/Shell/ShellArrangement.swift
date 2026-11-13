import SwiftUI

extension EnvironmentValues {
    /// Where around the screen the group being drawn sits, so it can open
    /// its menus and popups away from the edge.
    @Entry var shellSlot: ShellLayout.Slot = .bottomLeading
}

extension ShellLayout.Slot {
    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        side < 0 ? .leading : side > 0 ? .trailing : .center
    }
}

/// Lays groups out from a corner: the first sits in the corner, the rest
/// follow along the edge and wrap into rows growing away from it.
struct CornerFlow: Layout {
    let slot: ShellLayout.Slot
    var spacing: CGFloat = Metric.groupGap

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(Int, CGSize)]] = []
        var row: [(Int, CGSize)] = []
        var used: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let wanted = row.isEmpty ? size.width : used + spacing + size.width
            if !row.isEmpty, wanted > width {
                rows.append(row)
                row = [(i, size)]
                used = size.width
            } else {
                row.append((i, size))
                used = wanted
            }
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    private func width(of row: [(index: Int, size: CGSize)]) -> CGFloat {
        row.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        let heights = rows.map { $0.map(\.size.height).max() ?? 0 }
        return CGSize(width: rows.map(width(of:)).max() ?? 0,
                      height: heights.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = slot.isTop ? bounds.minY : bounds.maxY
        for row in rows(subviews, width: bounds.width) {
            let height = row.map(\.size.height).max() ?? 0
            var x: CGFloat = switch slot.side {
            case ..<0: bounds.minX
            case 1...: bounds.maxX
            default: bounds.midX - width(of: row) / 2
            }
            for (i, size) in row {
                let left: CGFloat
                if slot.side > 0 {
                    x -= size.width
                    left = x
                    x -= spacing
                } else {
                    left = x
                    x += size.width + spacing
                }
                subviews[i].place(at: CGPoint(x: left, y: slot.isTop ? y : y - size.height),
                                  anchor: .topLeading, proposal: ProposedViewSize(size))
            }
            y += slot.isTop ? height + spacing : -(height + spacing)
        }
    }
}

/// While arranging: the six places as outlines, the one under the dragged
/// group lit, and a card to finish or start over from a hand's arrangement.
struct ArrangeBoard: View {
    let size: CGSize
    let insets: EdgeInsets
    let target: ShellLayout.Slot?
    let leftHanded: Bool
    let reset: (Bool) -> Void
    let done: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .contentShape(Rectangle())
            ForEach(ShellLayout.Slot.allCases, id: \.self) { slot in
                let lit = slot == target
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Palette.ink.opacity(lit ? 0.7 : 0.25), style: StrokeStyle(lineWidth: lit ? 2.5 : 1.5, dash: [7, 6]))
                    .background(lit ? Palette.paper.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: slot.isTop ? .bottom : .top) {
                        Text(slot.name).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink.opacity(0.6)).padding(10)
                    }
                    .frame(width: size.width / 3 - 12, height: size.height / 2 - 12)
                    .position(x: size.width / 6 * CGFloat(2 * (slot.side + 1) + 1), y: slot.isTop ? size.height / 4 : size.height * 3 / 4)
            }
            VStack(spacing: 14) {
                Text("배치 바꾸기").font(.headline)
                Text("묶음을 끌어 놓을 자리에 내려놓으세요.\n같은 자리에 놓으면 모서리에서부터 차례로 붙습니다.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Chip(title: "오른손잡이 기본", selected: !leftHanded) { reset(false) }
                    Chip(title: "왼손잡이 기본", selected: leftHanded) { reset(true) }
                }
                Button("완료", action: done)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
            .position(x: size.width / 2, y: size.height / 2)
        }
    }
}
