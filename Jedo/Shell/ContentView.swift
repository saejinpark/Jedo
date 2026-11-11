import SwiftUI

struct ContentView: View {
    @State private var session = DrawingSession()

    var body: some View {
        ZStack {
            CanvasRepresentable(session: session)
                .ignoresSafeArea()

            VStack {
                if session.showsPencilHint {
                    PencilHint()
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
            .animation(.spring(duration: 0.35), value: session.showsPencilHint)
        }
        .preferredColorScheme(.light)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }
}

/// The ruler, then undo and redo (also on ⌘Z and ⇧⌘Z).
private struct HistoryControls: View {
    @Bindable var session: DrawingSession

    var body: some View {
        HStack(spacing: 10) {
            RoundToolButton(symbol: "ruler", label: session.rulerOnDesk ? "자 치우기" : "자 꺼내기",
                            enabled: true, selected: session.rulerOnDesk) {
                session.rulerOnDesk.toggle()
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

private struct PencilHint: View {
    var body: some View {
        Label("선은 Apple Pencil로 긋습니다. 손가락으로는 자를 잡습니다.", systemImage: "applepencil.tip")
            .font(.callout.weight(.medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

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
