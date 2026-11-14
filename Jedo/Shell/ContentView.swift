import PhotosUI
import UniformTypeIdentifiers
import SwiftUI

struct ContentView: View {
    @State private var session = DrawingSession()
    /// The arrangement of the control groups, kept between launches.
    @AppStorage("shellLayout3") private var savedLayout = ""
    @State private var arranging = false
    /// Whether the guide has been through once.
    @AppStorage("guideSeen") private var guideSeen = false
    @State private var showingGuide = false
    /// Asking what the controls are: a press explains a control instead of using it.
    @State private var helping = false
    @State private var helpTopic: Help.Topic?
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
                        // The layers card: 8 squares wide, as tall as its list, on the free squares nearest its button.
                        let panelRows = min(max(Int((CGFloat(60 + (session.layerRows.count + 1) * 44) / ShellLayout.unit).rounded(.up)), 2), max(grid.rows - 8, 2))
                        let panelCells: ShellLayout.Cells? = session.layersOpen && !arranging
                            ? cells[.sheets].flatMap { grid.freeBlock(w: min(8, grid.columns), h: panelRows, near: $0, avoiding: Array(cells.values)) }
                            : nil
                        if let panelCells {
                            let rect = grid.rect(panelCells)
                            ScrollView {
                                SheetsPanel(session: session)
                            }
                            .frame(width: rect.width - 2 * Metric.cardInset, height: rect.height - 2 * Metric.cardInset)
                            .card()
                            .position(x: rect.midX, y: rect.midY)
                            .transition(.opacity)
                        }
                        let spot = grid.hintSpot(avoiding: Array(cells.values) + (panelCells.map { [$0] } ?? []))
                        if let row = session.selectedRow, !arranging {
                            // What can be done with the sheet picked out, right where the eye is.
                            SheetBar(session: session, row: row)
                                .frame(width: spot.width, height: spot.height, alignment: .top)
                                .position(x: spot.midX, y: spot.midY)
                                .transition(.opacity)
                        }
                        if helping, !arranging {
                            if let c = cells[.map] {
                                let rect = grid.rect(c)
                                Color.white.opacity(0.001)
                                    .contentShape(Rectangle())
                                    .frame(width: rect.width, height: rect.height)
                                    .onTapGesture { helpTopic = Help.map }
                                    .position(x: rect.midX, y: rect.midY)
                            }
                            let topic = helpTopic ?? Help.asking
                            VStack(alignment: .leading, spacing: 4) {
                                Label(topic.title, systemImage: "questionmark.circle").font(.callout.weight(.bold))
                                Text(topic.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: min(spot.width - 8, 520), alignment: .leading)
                            .card(radius: Metric.hintRadius)
                            .position(x: spot.midX, y: spot.midY + ShellLayout.unit / 2)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                        } else if let hint = session.hint {
                            HintBubble(hint: hint)
                                .frame(maxWidth: min(spot.width - 8, 560))
                                .fixedSize(horizontal: false, vertical: true)
                                .position(x: spot.midX, y: session.selectedRow == nil ? spot.midY : spot.maxY + ShellLayout.unit / 2)
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
                .animation(.snappy(duration: 0.2), value: session.selectedSheet)
                .animation(.snappy(duration: 0.2), value: session.layersOpen)
                .animation(.snappy(duration: 0.2), value: session.layerRows.count)
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
            .environment(\.shellUpright, layout.isUpright(group))
            .frame(width: rect.width, height: rect.height, alignment: fromRight ? .topTrailing : .topLeading)
            .allowsHitTesting(!arranging)
            .overlay {
                if helping, !arranging {
                    // Asking: each square explains its control instead of working it.
                    let upright = layout.isUpright(group)
                    let towardEnd = upright ? c.y + c.h / 2 >= grid.rows / 2 : fromRight
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<(c.w * c.h), id: \.self) { k in
                            if let topic = Help.topic(group, column: k % c.w, row: k / c.w, w: c.w, h: c.h, upright: upright, towardEnd: towardEnd) {
                                RoundedRectangle(cornerRadius: Metric.cellRadius)
                                    .fill(Palette.go.opacity(helpTopic == topic ? 0.28 : 0.001))
                                    .frame(width: Metric.cell, height: Metric.cell)
                                    .contentShape(Rectangle())
                                    .onTapGesture { helpTopic = topic }
                                    .offset(x: CGFloat(k % c.w) * ShellLayout.unit + (ShellLayout.unit - Metric.cell) / 2,
                                            y: CGFloat(k / c.w) * ShellLayout.unit + (ShellLayout.unit - Metric.cell) / 2)
                            }
                        }
                    }
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                }
            }
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
                                    // A tap, not a drag: the group turns between lying and standing.
                                    if hypot(value.translation.width, value.translation.height) < 8 {
                                        if new.turn(group, columns: grid.columns, rows: grid.rows, withMap: mapShown) {
                                            withAnimation(.snappy(duration: 0.2)) { savedLayout = new.encoded }
                                        }
                                        dragging = nil
                                        dragOffset = .zero
                                        return
                                    }
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
        case .papers: PapersGroup(session: session)
        case .history: HistoryGroup(session: session)
        case .map: Color.clear
        case .view:
            ViewGroup(session: session, leftHanded: layout.leftHanded,
                      newPaper: {
                          session.throwAwayPaper()
                          session = DrawingSession()
                      },
                      hand: { savedLayout = ShellLayout.standard(leftHanded: $0).encoded },
                      arrange: { helping = false; arranging = true },
                      guide: { showingGuide = true },
                      helping: helping,
                      help: { helping.toggle(); helpTopic = nil })
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
                ValueFace(title: session.eraserKind.name)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("지우개 종류")
            ToolButton(icon: .symbol("compass.drawing"), label: session.compassOnDesk ? "컴퍼스 치우기" : "컴퍼스 꺼내기",
                       selected: session.compassOnDesk) {
                session.compassOnDesk.toggle()
            }
            ToolButton(icon: .hand(.cutter), label: session.knifeInHand ? "커터 내려놓기" : "커터 들기",
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
    @Environment(\.shellUpright) private var upright

    var body: some View {
        // Lying: holders over grades. Standing: holders beside grades, each a column.
        let stack = upright ? AnyLayout(HStackLayout(alignment: side.onTop ? .top : .bottom, spacing: 0))
                            : AnyLayout(VStackLayout(alignment: side.fromRight ? .trailing : .leading, spacing: 0))
        stack {
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
                TextCell(title: size.label, selected: session.holds(.mechanical(size))) {
                    session.instrument = .mechanical(size)
                }
                .accessibilityLabel(Instrument.mechanical(size).name)
            }
            GroupDivider()
            ToolButton(icon: .symbol("pencil"), label: Instrument.wood.name, selected: session.holds(.wood)) {
                session.instrument = .wood
            }
            GroupDivider()
            TechnicalPenMenu(session: session)
            ForEach(Nib.allCases, id: \.self) { nib in
                ToolButton(icon: .hand(nib == .gPen ? .gPen : .maruPen), label: nib.name, selected: session.holds(.dipPen(nib))) {
                    session.instrument = .dipPen(nib)
                }
            }
        }
    }
}

/// The technical pen, by line width: the face shows the width in hand.
private struct TechnicalPenMenu: View {
    @Bindable var session: DrawingSession

    var body: some View {
        let current: PenWidth? = if case .technicalPen(let w) = session.instrument, !session.knifeInHand { w } else { nil }
        Menu {
            ForEach(PenWidth.allCases, id: \.self) { width in
                Button {
                    session.instrument = .technicalPen(width)
                } label: {
                    Label("\(width.label)mm", systemImage: current == width ? "checkmark" : "")
                }
            }
        } label: {
            // The pen, and the width in hand written small beside its tip.
            ToolFace(icon: .hand(.technicalPen), selected: current != nil)
                .overlay(alignment: .bottomTrailing) {
                    if let current {
                        Text(current.label).font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white).padding(.trailing, 4).padding(.bottom, 3)
                    }
                }
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
            ToolButton(icon: .symbol("lines.measurement.horizontal"), label: session.tapeOut ? "줄자 넣기" : "줄자 꺼내기", selected: session.tapeOut) {
                session.tapeOut.toggle()
            }
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

/// The sheet picked out on the desk and everything that can be done to it,
/// one tap each: stamp, turn over, restack, hide, empty, put away.
private struct SheetBar: View {
    @Bindable var session: DrawingSession
    let row: DrawingSession.LayerRow

    var body: some View {
        // One row where it fits, else two: what is done to the sheet, then how it lies.
        ViewThatFits(in: .horizontal) {
            ControlGroup { name; doing; lying; close }
            VStack(spacing: 0) {
                ControlGroup { name; doing; close }
                ControlGroup { lying }
            }
        }
    }

    private var name: some View {
        TextFace(title: row.name, selected: false, width: 2 * ShellLayout.unit - 8)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder private var doing: some View {
        if row.isPhoto, !row.glued {
            ToolButton(icon: .symbol("pin"), label: "종이에 붙이기") { session.glueLayer(row.id) }
            ToolButton(icon: .symbol("drop.halffull"), label: row.photoCarbon ? "사진으로 쓰기" : "먹지로 쓰기",
                       selected: row.photoCarbon) {
                session.setPhotoCarbon(row.id, !row.photoCarbon)
            }
        }
        if row.canStamp {
            ToolButton(icon: .symbol("arrow.down.to.line.compact"), label: "그린 것 찍기") { session.stampLayer(row.id) }
            if row.hasPrint {
                ToolButton(icon: .symbol("printer"), label: "인쇄까지 찍기") { session.stampLayer(row.id, withPrint: true) }
            }
        }
        if !row.isCarbon && !row.isTone && !row.photoCarbon {
            ToolButton(icon: .symbol("eraser.line.dashed"), label: "비우기") { session.clearLayer(row.id) }
        }
        if let ink = row.carbonInk {
            Menu {
                ForEach(CarbonInk.allCases, id: \.self) { choice in
                    Button { session.setCarbonInk(row.id, choice) } label: {
                        Label(choice.name, systemImage: choice == ink ? "checkmark" : "")
                    }
                }
            } label: {
                CarbonSwatch(ink: ink, blend: row.carbonBlend, selected: false)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("먹지 색")
            if let blend = row.carbonBlend {
                BlendPickers(blend: blend) { session.setCarbonBlend(row.id, $0) }
            }
        }
    }

    @ViewBuilder private var lying: some View {
        if !row.glued {
            ToolButton(icon: .symbol("arrow.left.and.right.righttriangle.left.righttriangle.right"), label: "좌우로 뒤집기") {
                session.flipLayer(row.id, leftRight: true)
            }
            ToolButton(icon: .symbol("arrow.up.and.down.righttriangle.up.righttriangle.down"), label: "위아래로 뒤집기") {
                session.flipLayer(row.id, leftRight: false)
            }
            ToolButton(icon: .symbol("chevron.up"), label: "한 장 위로", enabled: row.canRaise) { session.shiftLayer(row.id, up: true) }
            ToolButton(icon: .symbol("chevron.down"), label: "한 장 아래로", enabled: row.canLower) { session.shiftLayer(row.id, up: false) }
        }
        ToolButton(icon: .symbol("eye.slash"), label: "숨기기") { session.setLayer(row.id, hidden: true) }
        ToolButton(icon: .symbol("trash"), label: "치우기") { session.removeLayer(row.id) }
    }

    private var close: some View {
        ToolButton(icon: .symbol("xmark"), label: "닫기") { session.selectSheet(nil) }
    }
}

/// Laying sheets on the paper, one button a kind, and what carbon is used
/// with: the stylus to press lines through, the roller to press bands.
private struct PapersGroup: View {
    @Bindable var session: DrawingSession
    @State private var pickingPhoto = false
    @State private var photoAsCarbon = false
    @State private var pickingPDF = false
    @State private var photoPick: PhotosPickerItem?

    var body: some View {
        ControlGroup {
            menu("트레이싱지", symbol: "doc.plaintext", GridPattern.allCases.filter { $0.isPlain || $0.isGraph }) { session.addSheet($0) }
            menu("원고지·공책", symbol: "doc.text", GridPattern.allCases.filter { !$0.isPlain && !$0.isGraph }) { session.addSheet($0) }
            Menu {
                ForEach(TonePattern.allCases, id: \.self) { p in Button(p.name) { session.addTone(p) } }
            } label: { ToolFace(icon: .symbol("circle.grid.3x3.fill")) }
                .menuStyle(.button).buttonStyle(.plain).accessibilityLabel("톤 얹기")
            Menu {
                Button { photoAsCarbon = false; pickingPhoto = true } label: { Label("사진 고르기", systemImage: "photo") }
                Button { pickingPDF = true } label: { Label("PDF 문서 가져오기", systemImage: "doc.richtext") }
            } label: { ToolFace(icon: .symbol("photo")) }
                .menuStyle(.button).buttonStyle(.plain).accessibilityLabel("사진·문서 얹기")
            Menu {
                ForEach(CarbonInk.allCases, id: \.self) { ink in Button("\(ink.name) 먹지") { session.addCarbon(ink) } }
                Divider()
                Button { photoAsCarbon = true; pickingPhoto = true } label: { Label("사진 먹지", systemImage: "photo") }
            } label: {
                CarbonSwatch(ink: .navy, selected: false).frame(width: Metric.cell, height: Metric.cell)
            }
            .menuStyle(.button).buttonStyle(.plain).accessibilityLabel("먹지 얹기")
            ToolButton(icon: .hand(.stylus), label: "철필", selected: session.holds(.stylus)) {
                session.instrument = .stylus
            }
            ToolButton(icon: .hand(.roller), label: "롤러", selected: session.holds(.roller)) {
                session.instrument = .roller
            }
        }
        .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { session.addPDF(at: url) }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoPick, matching: .images, photoLibrary: .shared())
        .onChange(of: photoPick) { _, item in
            guard let item else { return }
            photoPick = nil
            let asCarbon = photoAsCarbon
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                if asCarbon { session.addPhotoCarbon(data) } else { session.addPhoto(data) }
            }
        }
    }

    private func menu(_ title: String, symbol: String, _ patterns: [GridPattern], add: @escaping (GridPattern) -> Void) -> some View {
        Menu {
            ForEach(patterns, id: \.self) { p in Button(p.name) { add(p) } }
        } label: { ToolFace(icon: .symbol(symbol)) }
            .menuStyle(.button).buttonStyle(.plain).accessibilityLabel("\(title) 얹기")
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
    let helping: Bool
    let help: () -> Void
    @State private var confirmingNewPaper = false

    var body: some View {
        ControlGroup {
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
                Toggle(isOn: $session.edgeRulers) { Label("가장자리 눈금", systemImage: "ruler") }
                Button { guide() } label: { Label("처음 안내 다시 보기", systemImage: "book") }
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
            ToolButton(icon: .symbol("questionmark"), label: helping ? "설명 끝내기" : "이 버튼은 뭐지?", selected: helping, action: help)
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
                    .background(Palette.paper, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityHint("종이가 화면에 꼭 맞아 옮길 필요가 없습니다")
            Text("실제 크기로 책상에 고정됩니다. 화면은 지도와 조이스틱으로 옮겨 다닙니다.\n화면 맞춤은 지금 화면 그대로가 종이라 지도와 조이스틱이 없습니다.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .card(radius: Metric.panelRadius)
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
                            .fill(Palette.paper)
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

    var body: some View {
        // The list opens as a card on free squares of the grid, never over a group, and stays while working.
        ToolButton(icon: .symbol("square.3.layers.3d"), label: session.layersOpen ? "레이어 닫기" : "레이어 열기",
                   selected: session.layersOpen) {
            session.layersOpen.toggle()
        }
    }
}

private struct SheetsPanel: View {
    @Bindable var session: DrawingSession

    var body: some View {
        // Only what lies on the paper, top first: laying new sheets is the paper group's.
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
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
        }
        .padding(.vertical, 4)
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
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
            // Tapping the name picks the sheet out on the desk.
            Button { session.selectSheet(row.id) } label: {
                Text(row.name).lineLimit(1).opacity(row.hidden ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(row.hidden)
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
                    CarbonSwatch(ink: ink, blend: row.carbonBlend, selected: false).frame(width: 30, height: 30)
                }
                .accessibilityLabel("먹지 색")
                if let blend = row.carbonBlend {
                    BlendPickers(blend: blend) { session.setCarbonBlend(row.id, $0) }
                }
            }
            iconButton("trash", label: row.isCarbon ? "먹지 치우기" : "치우기 (그린 것도 함께)") { session.removeLayer(row.id) }
                .foregroundStyle(Palette.danger)
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

/// The two colours a mixed carbon runs between: the one at its left edge, the one at its right.
private struct BlendPickers: View {
    let blend: CarbonBlend
    let change: (CarbonBlend) -> Void

    private func binding(_ end: WritableKeyPath<CarbonBlend, [Double]>) -> Binding<Color> {
        Binding {
            let c = blend[keyPath: end]
            return Color(red: c[0], green: c[1], blue: c[2])
        } set: { colour in
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            guard UIColor(colour).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            var next = blend
            next[keyPath: end] = [Double(r), Double(g), Double(b)]
            change(CarbonBlend(from: next.from, to: next.to))
        }
    }

    var body: some View {
        ColorPicker("왼쪽 끝 색", selection: binding(\.from), supportsOpacity: false).labelsHidden()
            .frame(width: Metric.cell, height: Metric.cell)
        ColorPicker("오른쪽 끝 색", selection: binding(\.to), supportsOpacity: false).labelsHidden()
            .frame(width: Metric.cell, height: Metric.cell)
    }
}

/// A carbon's coating, as a small chip.
private struct CarbonSwatch: View {
    let ink: CarbonInk
    var blend: CarbonBlend? = nil
    let selected: Bool

    var body: some View {
        Canvas { context, size in
            // The coating in small: a plain colour, a run of colours, or a patch of the cloth print.
            let n = 13, m = 10
            for i in 0..<n {
                for j in 0..<m {
                    let t = Double(i) / Double(n - 1)
                    let c = ink.isPattern ? ink.printColour(atMM: Double(i) * 1.5 + 0.5, Double(j) * 1.5 + 0.5) : ink == .custom ? (blend ?? .standard).colour(at: t) : ink.colour(at: t)
                    context.fill(Path(CGRect(x: size.width * CGFloat(i) / CGFloat(n), y: size.height * CGFloat(j) / CGFloat(m),
                                             width: size.width / CGFloat(n) + 0.5, height: size.height / CGFloat(m) + 0.5)),
                                 with: .color(Color(red: c.r, green: c.g, blue: c.b)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metric.swatchRadius))
            .frame(width: 26, height: 20)
            .overlay(RoundedRectangle(cornerRadius: Metric.swatchRadius).strokeBorder(Palette.ink.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 2 : 0.5))
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
            .card(radius: Metric.hintRadius)
    }
}


#Preview {
    ContentView()
}
