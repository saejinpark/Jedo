import SwiftUI

struct ContentView: View {
    @State private var session = DrawingSession()

    var body: some View {
        ZStack {
            CanvasRepresentable(session: session)
                .ignoresSafeArea()

            VStack {
                if let hint = session.hint {
                    HintBubble(hint: hint)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    PencilTray(selection: $session.grade)
                    Spacer(minLength: 0)
                    ToolControls(session: session)
                }
            }
            .padding(20)
            .animation(.spring(duration: 0.35), value: session.hint)

            #if DEBUG
            if session.compassOnDesk {
                DraftPicker(session: session)
                    .padding(20)
                    .padding(.top, 60) // below the hint
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

/// The tools lying on the paper above; the compass, the eraser, undo and
/// redo (also on ⌘Z and ⇧⌘Z) below.
private struct ToolControls: View {
    @Bindable var session: DrawingSession

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ToolKind.allCases, id: \.self) { kind in
                    let onDesk = session.toolsOnDesk.contains(kind)
                    RoundToolButton(icon: ToolIcon(kind), label: onDesk ? "\(kind.name) 치우기" : "\(kind.name) 꺼내기",
                                    enabled: true, selected: onDesk) {
                        session.toggle(kind)
                    }
                }
            }
            HStack(spacing: 8) {
                RoundToolButton(icon: .symbol("compass.drawing"), label: session.compassOnDesk ? "컴퍼스 치우기" : "컴퍼스 꺼내기",
                                enabled: true, selected: session.compassOnDesk) {
                    session.compassOnDesk.toggle()
                }
                RoundToolButton(icon: .symbol("eraser"), label: session.eraserInHand ? "지우개 내려놓기" : "지우개 들기",
                                enabled: true, selected: session.eraserInHand) {
                    session.eraserInHand.toggle()
                }
                .padding(.trailing, 8)
                RoundToolButton(icon: .symbol("arrow.uturn.backward"), label: "실행 취소", enabled: session.canUndo) {
                    session.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                RoundToolButton(icon: .symbol("arrow.uturn.forward"), label: "다시 실행", enabled: session.canRedo) {
                    session.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}

/// What a round tool button shows.
private enum ToolIcon {
    case symbol(String)
    case shape(ToolKind)

    init(_ kind: ToolKind) {
        self = kind == .ruler ? .symbol("ruler") : .shape(kind)
    }
}

private struct RoundToolButton: View {
    let icon: ToolIcon
    let label: String
    let enabled: Bool
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                switch icon {
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: 18, weight: .semibold))
                case .shape(let kind):
                    ToolGlyph(kind: kind).frame(width: 24, height: 24)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.white : Palette.ink.opacity(enabled ? 0.85 : 0.25))
        .background(selected ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(.regularMaterial), in: Circle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .overlay(Circle().strokeBorder(Palette.ink.opacity(0.08)))
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// Small line drawings of the tools that have no system symbol.
private struct ToolGlyph: View {
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
            case .frenchCurve:
                path = Self.fitted(CurveTools.frenchCurveMM, in: size)
                path.addPath(Self.fitted(CurveTools.frenchCurveSlotOutlineMM, in: size, like: CurveTools.frenchCurveMM))
            case .hipCurve:
                path = Self.fitted(CurveTools.hipCurveMM, in: size)
            case .protractor:
                path = Self.fitted(Protractor.outlineMM, in: size)
            case .ruler:
                break
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
        case .setSquare45: "45° 삼각자"
        case .setSquare60: "30°·60° 삼각자"
        case .circleTemplate: "원형자"
        case .frenchCurve: "운형자"
        case .hipCurve: "대나무 커브자"
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

enum Palette {
    static let ink = Color(red: 0.16, green: 0.17, blue: 0.20)
    static let body = Color(red: 0.19, green: 0.25, blue: 0.30)
    static let bodyHighlight = Color(red: 0.31, green: 0.39, blue: 0.45)
    static let wood = Color(red: 0.89, green: 0.78, blue: 0.62)
    static let woodShade = Color(red: 0.76, green: 0.62, blue: 0.45)
    static let label = Color(red: 0.93, green: 0.88, blue: 0.74)
}

#Preview {
    ContentView()
}
