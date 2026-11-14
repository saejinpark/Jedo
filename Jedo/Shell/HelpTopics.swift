import Foundation

/// What each control is for, in two or three sentences: shown when a control is
/// pressed while asking ("?"), so nothing has to be learned before it is needed.
enum Help {
    struct Topic: Equatable {
        let title: String
        let text: String
    }

    private static let laying = "놓을 자리를 손가락으로 누르면 놓입니다. 한 손가락으로 밀고 두 손가락으로 돌리며, 가장자리 가까이 그으면 선이 따라갑니다. 버튼을 다시 누르면 치웁니다."

    static let asking = Topic(title: "이 버튼은 뭐지?", text: "궁금한 버튼을 누르면 설명이 나옵니다. 끝내려면 ? 를 다시 누르세요.")

    static let map = Topic(title: "지도와 조이스틱",
                           text: "화면보다 큰 종이를 옮겨 봅니다. 지도를 누르면 그 자리로 가고, 조이스틱은 미는 동안 움직입니다. 확대는 없습니다. 화면의 1cm가 종이의 1cm입니다.")

    private static let view: [Topic?] = [
        Topic(title: "내보내기", text: "그림을 PNG로 저장하거나 보냅니다. 종이만, 또는 얹힌 트레이싱지·톤·먹지까지 고를 수 있습니다."),
        Topic(title: "배치", text: "오른손·왼손 배치를 고르거나, 묶음을 직접 끌어 옮기고 톡 쳐서 세웁니다. 가장자리 눈금을 켜고 끄는 것과 처음 안내도 여기 있습니다."),
        Topic(title: "새 종이", text: "지금 종이를 치우고 새 종이를 깝니다. 되돌릴 수 없으니 남기려면 먼저 내보내세요."),
        nil,
    ]

    private static let holders: [Topic?] = ["0.3", "0.5", "0.7", "0.9"].map {
        Topic(title: "제도 샤프 \($0)mm", text: "굵기가 일정한 선을 긋습니다. 가는 심은 보조선에, 굵은 심은 외형선에 씁니다. 진하기는 심 경도에서 고릅니다.")
    } + [
        Topic(title: "연필", text: "세워 쥐면 가는 선, 눕혀 쥐면 넓은 면이 칠해집니다. 명암에 씁니다."),
        Topic(title: "제도펜", text: "눌러도 굵기가 변하지 않는 잉크 선입니다. 누르면 0.13~1.0mm 굵기를 고릅니다. 잉크는 지우개로 잘 지워지지 않습니다."),
        Topic(title: "G펜", text: "힘을 주면 굵어지고 빼면 가늘어지는 만화용 펜촉입니다. 외곽선에 씁니다."),
        Topic(title: "마루펜", text: "단단하고 가는 펜촉입니다. 세밀한 선과 해칭에 씁니다."),
    ]

    private static let grade = Topic(title: "심 경도", text: "H 쪽은 단단하고 옅어 보조선에, B 쪽은 무르고 진해 명암에 씁니다. 샤프와 연필에만 적용되고, 펜을 들면 흐려집니다.")

    private static let hand: [Topic?] = [
        Topic(title: "지우개", text: "들고 있는 동안 손가락으로 문지르면 지워집니다. 펜슬은 그대로 긋습니다. 다시 누르면 내려놓습니다."),
        Topic(title: "지우개 종류", text: "고무, 떡, 전동 지우개 중에 고릅니다. 지움판(구멍 안쪽만 지워지는 얇은 판)도 여기서 꺼냅니다."),
        Topic(title: "컴퍼스", text: "꺼낸 뒤 종이를 손가락으로 잠깐 누르고 있으면 바늘이 꽂힙니다. 펜슬을 대면 그곳까지 다리가 벌어지고, 돌리면 원이 그려집니다."),
        Topic(title: "커터", text: "얹힌 종이를 가로지르면 갈라지고, 한 바퀴 돌려 처음 자리로 오면 그 모양대로 오려집니다. 톤은 칼을 눕혀 문지르면 긁힙니다. 얹힌 종이가 있을 때만 쓸 수 있습니다."),
    ]

    private static let desk: [Topic?] = [
        Topic(title: "수평자", text: "판을 가로지르는 긴 자입니다. 위아래로만 움직여 늘 수평이고, 삼각자를 얹어 밀면 수직선과 사선을 긋습니다. " + laying),
        Topic(title: "자", text: "20cm 직선자입니다. " + laying),
        Topic(title: "45° 삼각자", text: "45°와 직각을 긋습니다. 수평자 위에 얹어 밀면 같은 각도의 선을 나란히 그을 수 있습니다. " + laying),
        Topic(title: "30·60° 삼각자", text: "30°, 60°와 직각을 긋습니다. " + laying),
        Topic(title: "삼각 스케일", text: "축척 눈금이 있는 자입니다. 메뉴에서 1:100 같은 면을 고릅니다. " + laying),
        Topic(title: "각도기", text: "각도를 재고 표시합니다. " + laying),
        Topic(title: "투시 핀", text: "소실점에 꽂습니다. 자를 핀에 밀어 대면 핀을 축으로 돌아서, 소실점으로 모이는 선을 긋습니다. 세 개까지 꽂고, 머리를 잡아 옮깁니다."),
        Topic(title: "형판", text: "원·타원·사각·육각 구멍과 레터링, 점자·모스 판입니다. 구멍 안쪽을 따라 그으면 그 모양이 됩니다. " + laying),
        Topic(title: "운형자", text: "자유 곡선을 이어 긋는 곡선자 세 가지입니다. 곡선에 맞는 부분을 찾아 대고 긋습니다. " + laying),
        Topic(title: "곡자", text: "옷본의 완만한 곡선을 긋는 긴 자입니다. " + laying),
        Topic(title: "줄자", text: "두 손가락으로 종이를 누르고 벌리면 그 사이에 줄자가 펴집니다. 눈금은 손가락 반대쪽 가장자리에 있고, 빨간 선에서 읽습니다. 끝을 잡으면 다시 옮길 수 있습니다."),
    ]

    private static let papers: [Topic?] = [
        Topic(title: "트레이싱지·모눈", text: "그림 위에 얹는 반투명 종이입니다. 그 위에 그리고, 가장자리를 잡아 옮기고, 톡 쳐서 고르면 찍기·뒤집기·치우기가 나옵니다."),
        Topic(title: "원고지·공책", text: "원고지, 만화 원고용지, 깍두기 공책, 오선지 같은 인쇄된 종이입니다. 트레이싱지처럼 얹고, 오리고, 찍습니다."),
        Topic(title: "스크린톤", text: "망점이나 사선이 인쇄된 필름입니다. 커터로 오려 남길 부분만 두고, 칼을 눕혀 긁어 빛을 냅니다."),
        Topic(title: "사진·PDF", text: "인쇄물처럼 종이에 얹습니다. 오려서 풀로 붙이면 콜라주가 됩니다. PDF는 첫 쪽이 실제 크기로 놓입니다."),
        Topic(title: "먹지", text: "얹고 그 위를 그으면 밑에 먹지 색으로 옮겨집니다. 단색, 그라데이션, 옷감 무늬, 사진이 있고, 오려서 롤러로 밀면 그 모양대로 찍힙니다."),
        Topic(title: "철필", text: "흑연 없이 홈만 냅니다. 먹지 위에서는 먹지 색 선이 되고, 종이에서는 그 위를 연필로 칠하면 홈이 하얗게 남습니다."),
        Topic(title: "롤러", text: "먹지 위를 굴릴 때만 찍힙니다. 굴린 폭 30mm만큼 먹지 색이 밑으로 옮겨지고, 세게 누를수록 진합니다."),
    ]

    private static let history: [Topic?] = [
        Topic(title: "실행 취소", text: "방금 한 일을 되돌립니다. 선, 지우기, 오리기, 찍기가 한 번에 하나씩 돌아갑니다."),
        Topic(title: "다시 실행", text: "되돌린 일을 다시 합니다."),
    ]

    private static let sheets = Topic(title: "레이어", text: "종이 위에 얹힌 것들의 목록을 엽니다. 순서를 바꾸고, 잠시 숨기고, 치웁니다. 열어 둔 채로 작업할 수 있습니다.")

    /// The topic for the control on square (`column`, `row`) of a group `w` by `h` squares.
    /// The pencil group is two runs, the holders shorter than the grades: `towardEnd` says the
    /// holders are set against the far end (right when lying, bottom when standing).
    static func topic(_ group: ShellLayout.Group, column: Int, row: Int, w: Int, h: Int, upright: Bool, towardEnd: Bool) -> Topic? {
        // Along the group's run, and which of its runs.
        let (along, run, length) = upright ? (row, column, h) : (column, row, w)
        func pick(_ list: [Topic?]) -> Topic? { list.indices.contains(along) ? list[along] : nil }
        switch group {
        case .view: return pick(view)
        case .hand: return pick(hand)
        case .desk: return pick(desk)
        case .papers: return pick(papers)
        case .history: return pick(history)
        case .sheets: return sheets
        case .map: return map
        case .pencil:
            guard run == 0 else { return (0..<length).contains(along) ? grade : nil }
            let i = along - (towardEnd ? length - holders.count : 0)
            return holders.indices.contains(i) ? holders[i] : nil
        }
    }
}
