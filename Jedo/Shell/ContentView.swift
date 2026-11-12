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
                    HistoryControls(session: session)
                }
            }
            .padding(20)
            .animation(.spring(duration: 0.35), value: session.hint)

            #if DEBUG
            if session.compassOnDesk {
                CompassDraftPicker(session: session)
                    .padding(20)
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

/// The ruler and the compass, then undo and redo (also on ⌘Z and ⇧⌘Z).
private struct HistoryControls: View {
    @Bindable var session: DrawingSession

    var body: some View {
        HStack(spacing: 10) {
            RoundToolButton(symbol: "ruler", label: session.rulerOnDesk ? "자 치우기" : "자 꺼내기",
                            enabled: true, selected: session.rulerOnDesk) {
                session.rulerOnDesk.toggle()
            }
            RoundToolButton(symbol: "compass.drawing", label: session.compassOnDesk ? "컴퍼스 치우기" : "컴퍼스 꺼내기",
                            enabled: true, selected: session.compassOnDesk) {
                session.compassOnDesk.toggle()
            }
            .padding(.trailing, 8)
            RoundToolButton(symbol: "arrow.uturn.backward", label: "실행 취소", enabled: session.canUndo) {
                session.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            RoundToolButton(symbol: "arrow.uturn.forward", label: "다시 실행", enabled: session.canRedo) {
                session.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }
}

private struct RoundToolButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 52, height: 52)
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
/// Compares compass handling drafts on the iPad. Goes once one is chosen.
private struct CompassDraftPicker: View {
    @Bindable var session: DrawingSession

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
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
