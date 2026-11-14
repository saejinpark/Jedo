import SwiftUI

struct ContentView: View {
    @State private var session = DrawingSession()
    /// The arrangement of the control groups, kept between launches.
    @AppStorage("shellLayout2") private var savedLayout = ""
    @State private var arranging = false
    /// Whether the guide has been through once.
    @AppStorage("guideSeen") private var guideSeen = false
    @State private var showingGuide = false
    @State private var dragging: ShellLayout.Group?
    @State private var dragOffset = CGSize.zero

    private var layout: ShellLayout { ShellLayout(encoded: savedLayout) ?? .standard(leftHanded: false) }
    private var mapShown: Bool { session.paper.map { !$0.fitsScreen } ?? false }

    var body: some View {
        ZStack {
            CanvasRepresentable(session: session)
                .id(ObjectIdentifier(session))
                .ignoresSafeArea()

            if session.paper == nil {
                PaperPicker { session.start(on: $0) }
            } else {
                GeometryReader { geo in
                    let grid = ShellGrid(size: geo.size, insets: geo.safeAreaInsets, edgeRulers: session.edgeRulers)
                    let cells = layout.cells(columns: grid.columns, rows: grid.rows, withMap: mapShown)
                    ZStack(alignment: .topLeading) {
                        if arranging {
                            ArrangeBoard(grid: grid, cells: cells, dragging: dragging, dragOffset: dragOffset,
                                         leftHanded: layout.leftHanded,
                                         reset: { savedLayout = ShellLayout.standard(leftHanded: $0).encoded },
                                         done: { arranging = false })
                        }
                        ForEach(ShellLayout.Group.allCases, id: \.self) { group in
                            if let c = cells[group], group != .map {
                                placed(group, at: c, grid: grid, cells: cells)
                            }
                        }
                        if arranging, let c = cells[.map] {
                            // The map is drawn by the desk; while arranging, a card stands in for it to drag.
                            placed(.map, at: c, grid: grid, cells: cells)
                        }
                        if let hint = session.hint {
                            let spot = grid.hintSpot(avoiding: Array(cells.values))
                            HintBubble(hint: hint)
                                .frame(maxWidth: min(spot.width - 8, 560))
                                .fixedSize(horizontal: false, vertical: true)
                                .position(x: spot.midX, y: spot.midY)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .onChange(of: cells[.map].map { grid.rect($0).origin }, initial: true) { _, origin in
                        session.mapOrigin = origin
                    }
                }
                .ignoresSafeArea()
                .animation(.spring(duration: 0.35), value: session.hint)
                .animation(.snappy(duration: 0.25), value: savedLayout)
            }
        }
        .overlay {
            if showingGuide || !guideSeen {
                GuideCards(leftHanded: layout.leftHanded,
                           chooseHand: { savedLayout = ShellLayout.standard(leftHanded: $0).encoded },
                           done: {
                               guideSeen = true
                               showingGuide = false
                           })
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: showingGuide)
        .animation(.snappy(duration: 0.25), value: guideSeen)
        .preferredColorScheme(.light)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }

    /// A group on its squares; while arranging, it is picked up and dropped on the grid instead of used.
    private func placed(_ group: ShellLayout.Group, at c: ShellLayout.Cells, grid: ShellGrid, cells: [ShellLayout.Group: ShellLayout.Cells]) -> some View {
        let rect = grid.rect(c)
        let fromRight = layout.leftHanded ? c.x + c.w / 2 > grid.columns / 2 : c.x + c.w / 2 > grid.columns / 2
        return groupView(group)
            .environment(\.shellSide, ShellSide(fromRight: fromRight, onTop: c.y + c.h / 2 < grid.rows / 2))
            .frame(width: rect.width, height: rect.height, alignment: fromRight ? .topTrailing : .topLeading)
            .allowsHitTesting(!arranging)
            .overlay {
                if arranging {
                    RoundedRectangle(cornerRadius: Metric.groupRadius)
                        .strokeBorder(Palette.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .background(group == .map ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear),
                                    in: RoundedRectangle(cornerRadius: Metric.groupRadius))
                        .overlay { if group == .map { Label("지도", systemImage: "map").font(.caption.weight(.semibold)) } }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragging = group
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    var new = layout
                                    let moved = ShellLayout.Cells(x: c.x + Int((value.translation.width / ShellLayout.unit).rounded()),
                                                                  y: c.y + Int((value.translation.height / ShellLayout.unit).rounded()),
                                                                  w: c.w, h: c.h)
                                    // Where another group already sits it goes back where it was.
                                    if new.place(group, at: moved, columns: grid.columns, rows: grid.rows, withMap: mapShown) {
                                        savedLayout = new.encoded
                                    }
                                    dragging = nil
                                    dragOffset = .zero
                                }
                        )
                }
            }
            .offset(x: rect.minX + (dragging == group ? dragOffset.width : 0),
                    y: rect.minY + (dragging == group ? dragOffset.height : 0))
            .zIndex(dragging == group ? 2 : 1)
    }

    @ViewBuilder
    private func groupView(_ group: ShellLayout.Group) -> some View {
        switch group {
        case .pencil: PencilGroup(session: session)
        case .hand: HandGroup(session: session)
        case .desk: DeskToolsGroup(session: session)
        case .sheets: SheetsGroup(session: session)
        case .history: HistoryGroup(session: session)
        case .map: Color.clear
        case .view:
            ViewGroup(session: session, leftHanded: layout.leftHanded,
                      newPaper: {
                          session.throwAwayPaper()
                          session = DrawingSession()
                      },
                      hand: { savedLayout = ShellLayout.standard(leftHanded: $0).encoded },
                      arrange: { arranging = true },
                      guide: { showingGuide = true })
        }
    }
}

/// What the off hand holds: the eraser and which one, the compass, the knife.
/// Always four squares: what can't be used now is dimmed, not taken away.
private struct HandGroup: View {
    @Bindable var session: DrawingSession

    var body: some View {
        ControlGroup {
            ToolButton(icon: .symbol("eraser"), label: session.eraserInHand ? "지우개 내려놓기" : "지우개 들기",
                       selected: session.eraserInHand) {
                session.eraserInHand.toggle()
            }
            Menu {
                ForEach(EraserKind.allCases, id: \.self) { kind in
                    Button {
                        session.eraserKind = kind
                        if !session.eraserInHand { session.eraserInHand = true }
                    } label: {
                        Label("\(kind.name)지우개", systemImage: session.eraserKind == kind ? "checkmark" : "")
                    }
                }
                Divider()
                let shieldOut = session.toolsOnDesk.contains(.erasingShield)
                Button(shieldOut ? "지움판 치우기" : "지움판 꺼내기") { session.toggle(.erasingShield) }
            } label: {
                TextFace(title: session.eraserKind.name, selected: false, width: Metric.cell)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("지우개 종류")
            ToolButton(icon: .symbol("compass.drawing"), label: session.compassOnDesk ? "컴퍼스 치우기" : "컴퍼스 꺼내기",
                       selected: session.compassOnDesk) {
                session.compassOnDesk.toggle()
            }
            ToolButton(icon: .symbol("scissors"), label: session.knifeInHand ? "커터 내려놓기" : "커터 들기",
                       enabled: session.canCut, selected: session.knifeInHand) {
                if session.canCut { session.knifeInHand.toggle() }
            }
        }
    }
}

/// The pencil hand's choices: what holds the lead, and the lead's grade.
private struct PencilGroup: View {
    @Bindable var session: DrawingSession
    @Environment(\.shellSide) private var side

    var body: some View {
        VStack(alignment: side.fromRight ? .trailing : .leading, spacing: 0) {
            InstrumentGroup(session: session)
            // Only lead has a grade: with ink or the stylus in hand the grades can't be chosen.
            ControlGroup { PencilGrades(selection: $session.grade) }
                .disabled(!session.instrument.hasGrade)
                .opacity(session.instrument.hasGrade ? 1 : 0.35)
        }
    }
}

/// What holds the lead: drafting mechanical pencils by lead size, for
/// lines, and a wood pencil, for shading on its side.
private struct InstrumentGroup: View {
    @Bindable var session: DrawingSession

    var body: some View {
        ControlGroup {
            ForEach(LeadSize.allCases, id: \.self) { size in
                TextCell(title: size.label, selected: session.instrument == .mechanical(size)) {
                    session.instrument = .mechanical(size)
                }
                .accessibilityLabel(Instrument.mechanical(size).name)
            }
            GroupDivider()
            ToolButton(icon: .symbol("pencil"), label: Instrument.wood.name, selected: session.instrument == .wood) {
                session.instrument = .wood
            }
            TextCell(title: "철필", selected: session.instrument == .stylus, width: 40) {
                session.instrument = .stylus
            }
            .accessibilityLabel("누름 막대")
            GroupDivider()
            TechnicalPenMenu(session: session)
            ForEach(Nib.allCases, id: \.self) { nib in
                TextCell(title: nib.label, selected: session.instrument == .dipPen(nib), width: 44) {
                    session.instrument = .dipPen(nib)
                }
                .accessibilityLabel(nib.name)
            }
        }
    }
}

/// The technical pen, by line width: the face shows the width in hand.
private struct TechnicalPenMenu: View {
    @Bindable var session: DrawingSession

    var body: some View {
        let current: PenWidth? = if case .technicalPen(let w) = session.instrument { w } else { nil }
        Menu {
            ForEach(PenWidth.allCases, id: \.self) { width in
                Button {
                    session.instrument = .technicalPen(width)
                } label: {
                    Label("\(width.label)mm", systemImage: current == width ? "checkmark" : "")
                }
            }
        } label: {
            TextFace(title: current.map { "펜 \($0.label)" } ?? "제도펜", selected: current != nil, width: 62)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(current.map { "제도펜 \($0.label)mm" } ?? "제도펜")
    }
}

/// The rigid tools that lie on the paper: straight edges, then the curves and templates.
private struct DeskToolsGroup: View {
    @Bindable var session: DrawingSession

    var body: some View {
        ControlGroup {
            tool(.parallelRule)
            tool(.ruler)
            tool(.setSquare45)
            tool(.setSquare60)
            ScaleRuleMenu(session: session)
            tool(.protractor)
            PinMenu(session: session)
            GroupDivider()
            ToolSetMenu(session: session, title: "형판", kinds: ToolKind.templates)
            ToolSetMenu(session: session, title: "운형자", kinds: ToolKind.frenchCurves)
            tool(.hipCurve)
        }
    }

    private func tool(_ kind: ToolKind) -> some View {
        let onDesk = session.toolsOnDesk.contains(kind)
        return ToolButton(icon: ToolIcon(kind), label: onDesk ? "\(kind.name) 치우기" : "\(kind.name) 꺼내기", selected: onDesk) {
            session.toggle(kind)
        }
    }
}

/// The triangular scale: take it out or put it away, and turn it to the face with the scales wanted.
private struct ScaleRuleMenu: View {
    @Bindable var session: DrawingSession

    var body: some View {
        let onDesk = session.toolsOnDesk.contains(.scaleRule)
        Menu {
            Button(onDesk ? "삼각 스케일 치우기" : "삼각 스케일 꺼내기") { session.toggle(.scaleRule) }
            Picker("면", selection: $session.scaleFace) {
                ForEach(ScaleRule.faces.indices, id: \.self) { face in
                    Text(ScaleRule.faceName(face)).tag(face)
                }
            }
            .pickerStyle(.inline)
        } label: {
            ToolFace(icon: .shape(.scaleRule), selected: onDesk)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuActionDismissBehavior(.disabled)
        .accessibilityLabel("삼각 스케일")
    }
}

/// Perspective pins: push one in at each vanishing point, and lay a straight
/// edge against it to swing it about the point.
private struct PinMenu: View {
    @Bindable var session: DrawingSession

    var body: some View {
        Menu {
            Button {
                session.addPin()
            } label: {
                Label(session.pinCount == 0 ? "핀 꽂기" : "핀 하나 더 꽂기", systemImage: "pin")
            }
            .disabled(session.pinCount >= CanvasView.maxPins)
            if session.pinCount > 0 {
                Button(role: .destructive) { session.removePins() } label: {
                    Label("핀 모두 뽑기", systemImage: "pin.slash")
                }
            }
        } label: {
            ToolFace(icon: .symbol("pin"), selected: session.pinCount > 0)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("투시 핀")
    }
}

/// The soft sheets: one panel to lay them on and order them.
private struct SheetsGroup: View {
    @Bindable var session: DrawingSession

    var body: some View {
        ControlGroup { SheetsButton(session: session) }
    }
}

/// Undo and redo (also ⌘Z and ⇧⌘Z).
private struct HistoryGroup: View {
    @Bindable var session: DrawingSession

    var body: some View {
        ControlGroup {
            ToolButton(icon: .symbol("arrow.uturn.backward"), label: "실행 취소", enabled: session.canUndo) {
                session.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            ToolButton(icon: .symbol("arrow.uturn.forward"), label: "다시 실행", enabled: session.canRedo) {
                session.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }
}

/// How the desk is shown, and taking the drawing away.
private struct ViewGroup: View {
    @Bindable var session: DrawingSession
    let leftHanded: Bool
    let newPaper: () -> Void
    /// Lay the groups out for the right hand (false) or the left (true).
    let hand: (Bool) -> Void
    let arrange: () -> Void
    let guide: () -> Void
    @State private var confirmingNewPaper = false

    var body: some View {
        ControlGroup {
            ToolButton(icon: .symbol("ruler.fill"), label: session.edgeRulers ? "가장자리 눈금 끄기" : "가장자리 눈금 켜기",
                       selected: session.edgeRulers) {
                session.edgeRulers.toggle()
            }
            Menu {
                Button("종이만") { session.export(includeSheets: false) }
                Button("얹힌 트레이싱지·먹지·톤까지") { session.export(includeSheets: true) }
            } label: {
                ToolFace(icon: .symbol("square.and.arrow.up"))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("내보내기")
            Menu {
                Button { hand(false) } label: {
                    Label("오른손잡이 배치", systemImage: leftHanded ? "" : "checkmark")
                }
                Button { hand(true) } label: {
                    Label("왼손잡이 배치", systemImage: leftHanded ? "checkmark" : "")
                }
                Divider()
                Button { arrange() } label: { Label("직접 옮기기…", systemImage: "hand.draw") }
                Divider()
                Button { guide() } label: { Label("사용법", systemImage: "questionmark.circle") }
            } label: {
                ToolFace(icon: .symbol("rectangle.3.group"))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("배치")
            ToolButton(icon: .symbol("doc.badge.plus"), label: "새 종이") {
                confirmingNewPaper = true
            }
            .confirmationDialog("지금 종이를 치우고 새 종이를 깔까요?", isPresented: $confirmingNewPaper, titleVisibility: .visible) {
                Button("치우고 새 종이 깔기", role: .destructive, action: newPaper)
            } message: {
                Text("그린 것과 얹힌 시트가 모두 사라지고 되돌릴 수 없습니다. 남기려면 먼저 내보내기를 하세요.")
            }
        }
    }
}

/// One button for a set of tools (the French curves, the templates): each
/// can be taken out or put away from its menu.
private struct ToolSetMenu: View {
    @Bindable var session: DrawingSession
    let title: String
    let kinds: [ToolKind]

    var body: some View {
        let anyOut = kinds.contains { session.toolsOnDesk.contains($0) }
        Menu {
            ForEach(kinds, id: \.self) { kind in
                Toggle(isOn: Binding(get: { session.toolsOnDesk.contains(kind) },
                                     set: { _ in session.toggle(kind) })) {
                    Text(kind.name)
                }
            }
        } label: {
            ToolFace(icon: .shape(kinds[0]), selected: anyOut)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuActionDismissBehavior(.disabled)
        .accessibilityLabel(title)
    }
}

/// Choosing the drawing paper, before anything else. It is laid on the
/// desk at its real size and stays put.
private struct PaperPicker: View {
    let choose: (PaperSize) -> Void
    @State private var landscape = false

    var body: some View {
        VStack(spacing: 22) {
            Text("종이 고르기").font(.title2.weight(.semibold))
            Picker("방향", selection: $landscape) {
                Text("세로").tag(false)
                Text("가로").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            row(PaperSize.Series.aSizes)
            row(PaperSize.Series.bSizes)
            Button { choose(PaperSize(series: .screen, landscape: false)) } label: {
                Label("화면 맞춤", systemImage: "ipad")
                    .font(.headline)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color(red: 0.965, green: 0.955, blue: 0.925), in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityHint("종이가 화면에 꼭 맞아 옮길 필요가 없습니다")
            Text("실제 크기로 책상에 고정됩니다. 화면은 지도와 조이스틱으로 옮겨 다닙니다.\n화면 맞춤은 지금 화면 그대로가 종이라 지도와 조이스틱이 없습니다.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .animation(.spring(duration: 0.3), value: landscape)
    }

    private func row(_ series: [PaperSize.Series]) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            ForEach(series, id: \.self) { series in
                let paper = PaperSize(series: series, landscape: landscape)
                Button { choose(paper) } label: {
                    VStack(spacing: 8) {
                        let (w, h) = paper.sizeMM
                        Rectangle()
                            .fill(Color(red: 0.965, green: 0.955, blue: 0.925))
                            .frame(width: w / 1189 * 125, height: h / 1189 * 125)
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        Text(paper.name).font(.headline)
                        Text(verbatim: "\(Int(w))×\(Int(h))mm").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 118, height: 180, alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(paper.name) \(landscape ? "가로" : "세로")")
            }
        }
    }
}

/// One place for every soft sheet: lay on grid sheets, tone and the carbon,
/// and see them as they lie over the paper, top first.
private struct SheetsButton: View {
    @Bindable var session: DrawingSession
    @Environment(\.shellSide) private var side
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            ToolFace(icon: .symbol("square.3.layers.3d"), selected: open || !session.layerRows.isEmpty)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("종이·시트")
        .popover(isPresented: $open, arrowEdge: side.onTop ? .top : .bottom) {
            SheetsPanel(session: session)
        }
    }
}

private struct SheetsPanel: View {
    @Bindable var session: DrawingSession

    var body: some View {
        // The list of what lies on the paper on top, what can be laid on below:
        // the popover grows upward from its arrow, so the buttons below stay
        // under the finger as the list lengthens.
        VStack(alignment: .leading, spacing: 0) {
            PanelSection(title: "레이어 (위에서부터)") {
                VStack(spacing: 0) {
                    ForEach(session.layerRows) { row in
                        layerRow(row)
                        Divider().padding(.leading, 52)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "doc").frame(width: 22)
                        Text("용지 (배경)")
                        Spacer()
                        iconButton("eraser.line.dashed", label: "용지 비우기") { session.clearLayer(nil) }
                            .foregroundStyle(Palette.ink)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            Divider()
            PanelSection(title: "먹지") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Chip(title: session.carbonOnDesk ? "먹지 치우기" : "먹지 깔기", selected: session.carbonOnDesk) {
                            session.carbonOnDesk.toggle()
                        }
                        Spacer()
                    }
                    // The coating of the next carbon laid; a carbon in the list above is recoated from its own row.
                    HStack(spacing: 6) {
                        ForEach(CarbonInk.allCases, id: \.self) { ink in
                            Button { session.carbonInk = ink } label: { CarbonSwatch(ink: ink, selected: session.carbonInk == ink) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("먹지 \(ink.name)")
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            Divider()
            PanelSection(title: "톤 얹기") {
                chips(TonePattern.allCases.map { p in (p.name, { session.addTone(p) }) })
            }
            Divider()
            PanelSection(title: "트레이싱지 얹기") {
                chips(GridPattern.allCases.filter { $0.isPlain || $0.isGraph }.map { p in (p.name, { session.addSheet(p) }) })
            }
            Divider()
            PanelSection(title: "원고지·공책 얹기") {
                chips(GridPattern.allCases.filter { !$0.isPlain && !$0.isGraph }.map { p in (p.name, { session.addSheet(p) }) },
                      perRow: 2)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 450)
    }

    private func chips(_ items: [(String, () -> Void)], perRow: Int = 3) -> some View {
        let rows = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r].indices, id: \.self) { i in Chip(title: rows[r][i].0, action: rows[r][i].1) }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func layerRow(_ row: DrawingSession.LayerRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol)
                .frame(width: 22)
                .foregroundStyle(row.isCarbon || row.isTone ? Palette.ink : Palette.ruling)
            Text(row.name).lineLimit(1).opacity(row.hidden ? 0.4 : 1)
            Spacer(minLength: 8)
            if row.canStamp && row.hasPrint {
                // Printed paper: the drawing alone, or the print with it (manuscript squares onto the paper).
                Menu {
                    Button("그린 것만 찍기") { session.stampLayer(row.id) }
                    Button("인쇄까지 찍기") { session.stampLayer(row.id, withPrint: true) }
                } label: {
                    Image(systemName: "arrow.down.to.line.compact").frame(width: 30, height: 30)
                }
                .accessibilityLabel("찍기")
            } else if row.canStamp {
                iconButton("arrow.down.to.line.compact", label: "종이에 찍기") { session.stampLayer(row.id) }
            }
            iconButton(row.hidden ? "eye.slash" : "eye", label: row.hidden ? "보이기" : "숨기기") {
                session.setLayer(row.id, hidden: !row.hidden)
            }
            iconButton("chevron.up", label: "위로", enabled: row.canRaise) { session.shiftLayer(row.id, up: true) }
            iconButton("chevron.down", label: "아래로", enabled: row.canLower) { session.shiftLayer(row.id, up: false) }
            if !row.isCarbon && !row.isTone {
                iconButton("eraser.line.dashed", label: "비우기") { session.clearLayer(row.id) }
            }
            if let ink = row.carbonInk {
                Menu {
                    ForEach(CarbonInk.allCases, id: \.self) { choice in
                        Button { session.setCarbonInk(row.id, choice) } label: {
                            Label(choice.name, systemImage: choice == ink ? "checkmark" : "")
                        }
                    }
                } label: {
                    CarbonSwatch(ink: ink, selected: false).frame(width: 30, height: 30)
                }
                .accessibilityLabel("먹지 색")
            }
            iconButton("trash", label: row.isCarbon ? "먹지 치우기" : "치우기 (그린 것도 함께)") { session.removeLayer(row.id) }
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func iconButton(_ symbol: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 30, height: 30) }
            .buttonStyle(.borderless)
            .disabled(!enabled)
            .accessibilityLabel(label)
    }
}

/// A carbon's coating, as a small chip.
private struct CarbonSwatch: View {
    let ink: CarbonInk
    let selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.25).map { t in
                let c = ink.colour(at: t)
                return Color(red: c.r, green: c.g, blue: c.b)
            }, startPoint: .leading, endPoint: .trailing))
            .frame(width: 26, height: 20)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.ink.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 2 : 0.5))
            .padding(2)
    }
}

/// Small line drawings of the tools that have no system symbol.
struct ToolGlyph: View {
    let kind: ToolKind

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var path = Path()
            switch kind {
            case .setSquare45:
                path.move(to: CGPoint(x: 2, y: h - 2))
                path.addLine(to: CGPoint(x: w - 2, y: h - 2))
                path.addLine(to: CGPoint(x: 2, y: 2))
                path.closeSubpath()
            case .setSquare60:
                path.move(to: CGPoint(x: 1, y: h - 4))
                path.addLine(to: CGPoint(x: w - 1, y: h - 4))
                path.addLine(to: CGPoint(x: 1, y: h - 4 - (w - 2) / 3.0.squareRoot()))
                path.closeSubpath()
            case .circleTemplate:
                path.addRoundedRect(in: CGRect(x: 1, y: 5, width: w - 2, height: h - 10), cornerSize: CGSize(width: 2, height: 2))
                path.addEllipse(in: CGRect(x: 4, y: 9, width: 4, height: 4))
                path.addEllipse(in: CGRect(x: 10, y: 8.5, width: 5, height: 5))
                path.addEllipse(in: CGRect(x: 16.5, y: 8, width: 6, height: 6).insetBy(dx: 0.5, dy: 0.5))
            case .frenchCurveA, .frenchCurveB, .frenchCurveC:
                let outline = FrenchCurve.outline(kind)
                path = Self.fitted(outline, in: size)
                for slot in FrenchCurve.slots(kind) { path.addPath(Self.fitted(slot, in: size, like: outline)) }
            case .brailleSlate:
                path.addRoundedRect(in: CGRect(x: 1, y: 4, width: w - 2, height: h - 8), cornerSize: CGSize(width: 2, height: 2))
                for cx in [6.0, 14.0] {
                    for dx in [0.0, 3.0] {
                        for dy in [0.0, 3.0, 6.0] { path.addEllipse(in: CGRect(x: cx + dx - 0.9, y: 8 + dy - 0.9, width: 1.8, height: 1.8)) }
                    }
                }
            case .morsePlate:
                path.addRoundedRect(in: CGRect(x: 1, y: 4, width: w - 2, height: h - 8), cornerSize: CGSize(width: 2, height: 2))
                path.addEllipse(in: CGRect(x: 4, y: h / 2 - 1.5, width: 3, height: 3))
                path.addRoundedRect(in: CGRect(x: 10, y: h / 2 - 1.5, width: 9, height: 3), cornerSize: CGSize(width: 1.5, height: 1.5))
            case .erasingShield:
                path.addRoundedRect(in: CGRect(x: 1, y: 4, width: w - 2, height: h - 8), cornerSize: CGSize(width: 2, height: 2))
                for y in [8.0, 11.0] {
                    path.move(to: CGPoint(x: 4, y: y))
                    path.addLine(to: CGPoint(x: w - 10, y: y))
                }
                path.addEllipse(in: CGRect(x: w - 8, y: 7, width: 4, height: 4))
                path.addRect(CGRect(x: 4, y: h - 9, width: 3, height: 3))
            case .scaleRule:
                path.addRect(CGRect(x: 0.5, y: h * 0.3, width: w - 1, height: h * 0.4))
                path.move(to: CGPoint(x: 0.5, y: h * 0.5))
                path.addLine(to: CGPoint(x: w - 0.5, y: h * 0.5))
                for x in stride(from: 3.0, to: w - 1, by: 3) {
                    path.move(to: CGPoint(x: x, y: h * 0.3))
                    path.addLine(to: CGPoint(x: x, y: h * 0.38))
                }
            case .letteringGuide:
                path.addRoundedRect(in: CGRect(x: 1, y: 4, width: w - 2, height: h - 8), cornerSize: CGSize(width: 2, height: 2))
                for y in [8.0, 10.5, 14.0, 17.0] {
                    path.move(to: CGPoint(x: 4, y: y))
                    path.addLine(to: CGPoint(x: w - 8, y: y))
                }
                path.move(to: CGPoint(x: w - 5, y: 7))
                path.addLine(to: CGPoint(x: w - 4, y: h - 7))
            case .arcTemplate:
                path.addRect(CGRect(x: 2, y: 2, width: w - 4, height: h - 4))
                for r in [6.0, 11, 16] {
                    path.move(to: CGPoint(x: 4, y: h - 4 - r))
                    path.addArc(center: CGPoint(x: 4, y: h - 4), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                }
            case .ellipseTemplate, .squareTemplate, .hexTemplate:
                let sheet = ShapeTemplate.size(kind)
                let frame = [CGPoint(x: -sheet.width / 2, y: -sheet.height / 2), CGPoint(x: sheet.width / 2, y: sheet.height / 2)]
                path.addRoundedRect(in: CGRect(x: 1, y: 5, width: w - 2, height: h - 10), cornerSize: CGSize(width: 2, height: 2))
                for cut in ShapeTemplate.cuts(kind).prefix(6) { path.addPath(Self.fitted(cut.outline, in: size, like: frame)) }
            case .hipCurve:
                path = Self.fitted(CurveTools.hipCurveMM, in: size)
            case .protractor:
                path = Self.fitted(Protractor.outlineMM, in: size)
            case .ruler:
                break
            case .parallelRule:
                path.addRect(CGRect(x: 0.5, y: h * 0.38, width: w - 1, height: h * 0.24))
                path.addRect(CGRect(x: 0.5, y: h * 0.38, width: 3, height: h * 0.24))
                path.addRect(CGRect(x: w - 3.5, y: h * 0.38, width: 3, height: h * 0.24))
            }
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }
    }

    /// An outline scaled to fit `size`, or placed as `reference` would be.
    static func fitted(_ points: [CGPoint], in size: CGSize, like reference: [CGPoint]? = nil) -> Path {
        let frame = reference ?? points
        let xs = frame.map(\.x), ys = frame.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        let w = max((xs.max() ?? 1) - minX, 1e-6), h = max((ys.max() ?? 1) - minY, 1e-6)
        let k = min((size.width - 3) / w, (size.height - 3) / h)
        let dx = (size.width - w * k) / 2, dy = (size.height - h * k) / 2
        var path = Path()
        for (i, p) in points.enumerated() {
            let q = CGPoint(x: (p.x - minX) * k + dx, y: (p.y - minY) * k + dy)
            i == 0 ? path.move(to: q) : path.addLine(to: q)
        }
        path.closeSubpath()
        return path
    }
}

extension ToolKind {
    var name: String {
        switch self {
        case .ruler: "자"
        case .parallelRule: "평행자"
        case .setSquare45: "45° 삼각자"
        case .setSquare60: "30°·60° 삼각자"
        case .circleTemplate: "원 형판"
        case .ellipseTemplate, .squareTemplate, .hexTemplate, .arcTemplate: "\(ShapeTemplate.name(self)) 형판"
        case .letteringGuide: "레터링 가이드"
        case .scaleRule: "삼각 스케일"
        case .erasingShield: "지움판"
        case .brailleSlate: "점판"
        case .morsePlate: "모스 부호판"
        case .frenchCurveA, .frenchCurveB, .frenchCurveC:
            "운형자 \((ToolKind.frenchCurves.firstIndex(of: self) ?? 0) + 1) · \(FrenchCurve.form(self)?.name ?? "")"
        case .hipCurve: "대나무 곡자"
        case .protractor: "각도기"
        }
    }
}

private struct HintBubble: View {
    let hint: DrawingSession.Hint

    var body: some View {
        Label(hint.text, systemImage: hint.symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(Palette.ink)
            .lineLimit(3)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}


#Preview {
    ContentView()
}
