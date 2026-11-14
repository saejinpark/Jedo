import SwiftUI

/// Which side of the screen a group sits on, so it can line its rows up
/// with the edge and open its popups away from it.
struct ShellSide: Equatable {
    var fromRight = false
    var onTop = false
}

extension EnvironmentValues {
    @Entry var shellSide = ShellSide()
    /// Whether the group a control is in stands upright: its buttons in a column.
    @Entry var shellUpright = false
}

/// The screen's grid of squares, `ShellLayout.unit` on a side, inside the
/// margins and clear of the edge rulers, centred so the slack is shared.
struct ShellGrid {
    let columns: Int
    let rows: Int
    let origin: CGPoint
    let size: CGSize

    init(size: CGSize, insets: EdgeInsets, edgeRulers: Bool) {
        let u = ShellLayout.unit
        let ruler = edgeRulers ? EdgeRulerView.thickness + 6 : 10
        let left = max(insets.leading, 0) + ruler, top = max(insets.top, 0) + ruler
        let right = max(insets.trailing, 0) + 10, bottom = max(insets.bottom, 0) + 8
        let width = max(size.width - left - right, 0), height = max(size.height - top - bottom, 0)
        columns = max(Int(width / u), 1)
        rows = max(Int(height / u), 1)
        origin = CGPoint(x: left + (width - CGFloat(columns) * u) / 2, y: top + (height - CGFloat(rows) * u) / 2)
        self.size = size
    }

    func rect(_ c: ShellLayout.Cells) -> CGRect {
        let u = ShellLayout.unit
        return CGRect(x: origin.x + CGFloat(c.x) * u, y: origin.y + CGFloat(c.y) * u, width: CGFloat(c.w) * u, height: CGFloat(c.h) * u)
    }

    /// A free block of squares `w` by `h`, the one nearest `near`: where a card
    /// (the layers list) can open without covering any group.
    func freeBlock(w: Int, h: Int, near: ShellLayout.Cells, avoiding taken: [ShellLayout.Cells]) -> ShellLayout.Cells? {
        var best: (ShellLayout.Cells, Int)?
        guard w <= columns, h <= rows else { return nil }
        for y in 0...(rows - h) {
            for x in 0...(columns - w) {
                let c = ShellLayout.Cells(x: x, y: y, w: w, h: h)
                guard !taken.contains(where: c.overlaps) else { continue }
                // Distance between the block and the button, edge to edge.
                let dx = max(near.x - (x + w - 1), x - (near.x + near.w - 1), 0)
                let dy = max(near.y - (y + h - 1), y - (near.y + near.h - 1), 0)
                let d = dx + dy
                if best == nil || d < best!.1 { best = (c, d) }
            }
        }
        return best?.0
    }

    /// Where a passing hint sits: the widest run of free squares in the
    /// highest two free rows, so it never covers a group or the map.
    func hintSpot(avoiding taken: [ShellLayout.Cells]) -> CGRect {
        let u = ShellLayout.unit
        for r in 0..<max(rows - 1, 1) {
            var best: (x: Int, w: Int) = (0, 0), run = 0
            for c in 0..<columns {
                let free = !taken.contains { $0.overlaps(ShellLayout.Cells(x: c, y: r, w: 1, h: 2)) }
                run = free ? run + 1 : 0
                if run > best.w { best = (c - run + 1, run) }
            }
            if best.w >= min(8, columns) {
                return CGRect(x: origin.x + CGFloat(best.x) * u, y: origin.y + CGFloat(r) * u, width: CGFloat(best.w) * u, height: 2 * u)
            }
        }
        return CGRect(x: origin.x, y: origin.y + CGFloat(rows / 3) * u, width: CGFloat(columns) * u, height: 2 * u)
    }
}

/// While arranging: the grid over the whole screen, the squares a dragged
/// group would land on (green when free, red when taken), and a card to
/// finish or start again from a hand's arrangement.
struct ArrangeBoard: View {
    let grid: ShellGrid
    let cells: [ShellLayout.Group: ShellLayout.Cells]
    let dragging: ShellLayout.Group?
    let dragOffset: CGSize
    let leftHanded: Bool
    let reset: (Bool) -> Void
    let done: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.14)
                .contentShape(Rectangle())
            Canvas { context, _ in
                let u = ShellLayout.unit
                var lines = Path()
                for c in 0...grid.columns {
                    let x = grid.origin.x + CGFloat(c) * u
                    lines.move(to: CGPoint(x: x, y: grid.origin.y))
                    lines.addLine(to: CGPoint(x: x, y: grid.origin.y + CGFloat(grid.rows) * u))
                }
                for r in 0...grid.rows {
                    let y = grid.origin.y + CGFloat(r) * u
                    lines.move(to: CGPoint(x: grid.origin.x, y: y))
                    lines.addLine(to: CGPoint(x: grid.origin.x + CGFloat(grid.columns) * u, y: y))
                }
                context.stroke(lines, with: .color(Palette.ink.opacity(0.18)), lineWidth: 0.5)
                if let group = dragging, let from = cells[group] {
                    let to = ShellLayout.Cells(x: from.x + Int((dragOffset.width / u).rounded()),
                                               y: from.y + Int((dragOffset.height / u).rounded()), w: from.w, h: from.h)
                    let inside = to.x >= 0 && to.y >= 0 && to.x + to.w <= grid.columns && to.y + to.h <= grid.rows
                    let free = inside && !cells.contains { $0.key != group && $0.value.overlaps(to) }
                    let colour = free ? Palette.go : Palette.danger
                    context.fill(Path(roundedRect: grid.rect(to), cornerRadius: Metric.groupRadius), with: .color(colour.opacity(0.22)))
                }
            }
            VStack(spacing: 14) {
                Text(tr("배치 바꾸기")).font(.headline)
                Text(tr("묶음을 끌어 모눈 위에 놓으세요. 다른 묶음이 있는 칸에는 놓이지 않습니다.\n묶음을 톡 치면 세로로 서고, 다시 치면 눕습니다.\n가까운 모서리에서 몇 칸인지로 기억해서, 아이패드를 돌려도 그 모서리에 남습니다."))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Chip(title: tr("오른손잡이 기본"), selected: !leftHanded) { reset(false) }
                    Chip(title: tr("왼손잡이 기본"), selected: leftHanded) { reset(true) }
                }
                Button(tr("완료"), action: done)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
            }
            .padding(22)
            .frame(width: 400)
            .card(radius: Metric.panelRadius)
            .position(x: grid.size.width / 2, y: grid.size.height / 2)
        }
        .frame(width: grid.size.width, height: grid.size.height)
    }
}
