import SwiftUI

struct ContentView: View {
    @State private var session = DrawingSession()

    var body: some View {
        ZStack {
            CanvasRepresentable(session: session)
                .id(ObjectIdentifier(session))
                .ignoresSafeArea()

            if session.paper == nil {
                PaperPicker { session.start(on: $0) }
            } else {
            VStack(spacing: 0) {
                if let hint = session.hint {
                    HintBubble(hint: hint)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                // The pencils and the desk tools on a row of their own, so both rows fit an upright iPad.
                HStack(alignment: .bottom) {
                    InstrumentGroup(session: session)
                    Spacer(minLength: 0)
                    DeskToolsGroup(session: session)
                }
                .padding(.bottom, Metric.groupGap)
                HStack(alignment: .bottom, spacing: Metric.groupGap) {
                    HandGroup(session: session)
                    Spacer(minLength: 0)
                    SheetsGroup(session: session)
                    HistoryGroup(session: session)
                }
            }
            .padding(Metric.margin)
            .animation(.spring(duration: 0.35), value: session.hint)

            ViewGroup(session: session) {
                session.throwAwayPaper()
                session = DrawingSession()
            }
                .padding(.top, 34)
                .padding(.trailing, Metric.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            #if DEBUG
            if session.compassOnDesk {
                DraftPicker(session: session)
                    .padding(20)
                    .padding(.top, 96) // below the hint and the export button
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            #endif
        }
        .preferredColorScheme(.light)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }
}

/// What is in hand: the pencil's grade, and the eraser and compass the
/// fingers use. One group, because they are what the hands hold.
private struct HandGroup: View {
    @Bindable var session: DrawingSession

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.groupGap) {
            if session.eraserInHand {
                // Which eraser, while one is in hand: a small group over the hand.
                ControlGroup {
                    ForEach(EraserKind.allCases, id: \.self) { kind in
                        TextCell(title: kind.name, selected: session.eraserKind == kind) { session.eraserKind = kind }
                            .accessibilityLabel("\(kind.name)지우개")
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            ControlGroup {
                PencilGrades(selection: $session.grade)
                GroupDivider()
                ToolButton(icon: .symbol("eraser"), label: session.eraserInHand ? "지우개 내려놓기" : "지우개 들기",
                           selected: session.eraserInHand) {
                    session.eraserInHand.toggle()
                }
                ToolButton(icon: .symbol("compass.drawing"), label: session.compassOnDesk ? "컴퍼스 치우기" : "컴퍼스 꺼내기",
                           selected: session.compassOnDesk) {
                    session.compassOnDesk.toggle()
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: session.eraserInHand)
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
        }
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

/// The soft sheets: one panel to lay them on and order them, and the knife
/// beside it whenever there is tone to cut.
private struct SheetsGroup: View {
    @Bindable var session: DrawingSession

    var body: some View {
        ControlGroup {
            SheetsButton(session: session)
            if session.hasTone {
                ToolButton(icon: .symbol("scissors"), label: session.knifeInHand ? "커터 내려놓기" : "커터 들기",
                           selected: session.knifeInHand) {
                    session.knifeInHand.toggle()
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: session.hasTone)
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
    let newPaper: () -> Void
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
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            ToolFace(icon: .symbol("square.3.layers.3d"), selected: open || !session.layerRows.isEmpty)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("종이·시트")
        .popover(isPresented: $open, arrowEdge: .bottom) {
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
                HStack {
                    Chip(title: session.carbonOnDesk ? "먹지 치우기" : "먹지 깔기", selected: session.carbonOnDesk) {
                        session.carbonOnDesk.toggle()
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            Divider()
            PanelSection(title: "톤 얹기") {
                chips(TonePattern.allCases.map { p in (p.name, { session.addTone(p) }) })
            }
            Divider()
            PanelSection(title: "트레이싱지 얹기") {
                chips(GridPattern.allCases.map { p in (p.name, { session.addSheet(p) }) })
            }
        }
        .padding(.vertical, 4)
        .frame(width: 450)
    }

    private func chips(_ items: [(String, () -> Void)]) -> some View {
        // Two rows at most at this width.
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
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
            if row.canStamp {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

#if DEBUG
/// Compares hand-feel drafts on the iPad. Each row goes once its draft is chosen.
private struct DraftPicker: View {
    @Bindable var session: DrawingSession

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            if session.compassOnDesk {
            GridRow {
                Text("컴퍼스 시안").font(.caption.weight(.semibold)).gridCellColumns(2)
            }
            GridRow {
                Text("다리").font(.caption)
                Picker("다리", selection: $session.compassStyle.spread) {
                    Text("닿을 때마다 벌림").tag(CompassStyle.Spread.eachTouch)
                    Text("벌린 폭 유지").tag(CompassStyle.Spread.kept)
                }
                .pickerStyle(.segmented)
            }
            GridRow {
                Text("바늘").font(.caption)
                Picker("바늘", selection: $session.compassStyle.needle) {
                    Text("누르는 동안").tag(CompassStyle.Needle.whileHeld)
                    Text("꽂아 둠").tag(CompassStyle.Needle.planted)
                }
                .pickerStyle(.segmented)
            }
            }
        }
        .foregroundStyle(Palette.ink)
        .frame(width: 300)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}
#endif

#Preview {
    ContentView()
}
