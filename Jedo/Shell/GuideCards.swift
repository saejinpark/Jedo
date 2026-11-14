import SwiftUI

/// The first thing a new hand sees: which hand draws, and how the desk is
/// worked. A few cards, shown once and kept in the arrangement menu.
struct GuideCards: View {
    let leftHanded: Bool
    /// Lays the controls out for the left hand (true) or the right.
    let chooseHand: (Bool) -> Void
    let done: () -> Void
    @State private var page = 0

    private struct Card {
        let symbol: String
        let title: String
        let text: String
    }

    private let cards: [Card] = [
        Card(symbol: "applepencil.tip", title: "펜슬은 긋고, 손가락은 잡습니다",
             text: "선은 Apple Pencil로만 그어집니다. 손가락으로는 자와 종이를 잡고, 지우개로 문지르고, 컴퍼스 바늘을 꽂습니다. 확대는 없습니다. 화면의 1cm가 종이의 1cm입니다."),
        Card(symbol: "ruler", title: "자는 손으로 옮깁니다",
             text: "버튼으로 자·삼각자·형판을 들고, 놓을 자리를 손가락으로 누릅니다. 다른 도구가 있는 자리에는 놓이지 않습니다. 한 손가락으로 밀고 두 손가락으로 돌립니다. 가장자리 가까이 대고 그으면 선이 자를 따라갑니다. 평행자 위에 삼각자를 얹어 밀 수 있습니다."),
        Card(symbol: "compass.drawing", title: "컴퍼스는 바늘부터",
             text: "컴퍼스를 꺼낸 뒤 종이를 손가락으로 잠깐 누르고 있으면 바늘이 꽂힙니다. 펜슬이 닿은 곳까지 다리가 벌어지고, 펜슬을 돌리면 원이 그려집니다. 바로 손을 떼면 바늘이 남고, 누른 채 그리고 떼면 같이 빠집니다."),
        Card(symbol: "square.3.layers.3d", title: "종이를 얹고, 오리고, 찍습니다",
             text: "시트 버튼에서 트레이싱지·원고지·톤·먹지를 얹습니다. 가장자리를 잡아 옮기고, 커터로 오리고, 찍기로 밑의 종이에 옮깁니다. 그림은 저절로 저장되고, 오른쪽 위에서 내보내거나 새 종이를 깝니다."),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            VStack(spacing: 20) {
                Group {
                    if page == 0 { handPage } else { cardPage(cards[page - 1]) }
                }
                .frame(height: 300)
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                HStack(spacing: 6) {
                    ForEach(0...cards.count, id: \.self) { i in
                        Circle().fill(Palette.ink.opacity(i == page ? 0.8 : 0.2)).frame(width: 7, height: 7)
                    }
                }
                HStack {
                    if page > 0 {
                        Button("이전") { withAnimation(.snappy) { page -= 1 } }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(page == cards.count ? "시작하기" : "다음") {
                        if page == cards.count { done() } else { withAnimation(.snappy) { page += 1 } }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                }
            }
            .padding(28)
            .frame(width: 460)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: Metric.panelRadius))
            .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
            .clipped()
        }
    }

    private var handPage: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.raised").font(.system(size: 40, weight: .light)).foregroundStyle(Palette.ink)
            Text("어느 손으로 그리세요?").font(.title3.weight(.semibold))
            Text("펜슬을 쥔 손 쪽 위에 연필 고르기가, 다른 손 쪽 아래에 실행 취소와 도구가 놓입니다. 그리는 손바닥에 버튼이 눌리지 않게요. 나중에 배치 메뉴에서 바꾸거나 직접 옮길 수 있습니다.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Chip(title: "오른손", selected: !leftHanded) { chooseHand(false) }
                Chip(title: "왼손", selected: leftHanded) { chooseHand(true) }
            }
        }
        .foregroundStyle(Palette.ink)
    }

    private func cardPage(_ card: Card) -> some View {
        VStack(spacing: 18) {
            Image(systemName: card.symbol).font(.system(size: 40, weight: .light))
            Text(card.title).font(.title3.weight(.semibold))
            Text(card.text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .foregroundStyle(Palette.ink)
    }
}
