# 제도 (Jedo, 가제)

아이패드에서 실제 자·삼각자·컴퍼스·원형자를 손으로 다루고 연필로 긋는 감각을 익히는 손제도 앱.
CAD가 아니다. 치수 입력, 도형 자동 생성, 레이어는 없다.

## 지금 상태: 마일스톤 1

- 종이 질감 위에 연필 7종(HB, B, 2B–6B)으로 긋는다.
- 펜슬만 긋는다. 손가락은 이후 도구 조작용으로 비워 두었다(손가락이 종이에 닿으면 안내가 잠깐 뜬다).
- 필압이 셀수록 굵고 진하며 종이결 골까지 흑연이 들어간다.
- 펜슬을 50° 아래로 눕히면 심의 옆면이 닿아 넓고 옅은 면이 되고 종이결이 더 드러난다.
- 같은 자리를 다시 그으면 진해지지만 경도마다 한계 농도가 있다(HB는 6B만큼 진해지지 않는다).
- 실행 취소/다시 실행: 화면 버튼, 또는 ⌘Z / ⇧⌘Z.

## 실행

Xcode에서 `Jedo.xcodeproj`를 열고 아이패드(iPadOS 27 이상)를 골라 실행한다.
시뮬레이터에서는 마우스가 펜슬 대신 그린다(필압 0.5 고정, 기울기 없음).

```bash
xcodebuild -project Jedo.xcodeproj -scheme Jedo -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' test
```

## 구조

- `Jedo/Core/` — UIKit 없는 순수 로직. 단위 테스트 대상이고 맥에서도 컴파일된다.
  - `PencilGrade` 경도표, `PencilDynamics` 필압·기울기 반응, `PressureCurve` 펜슬 force 정규화
  - `DabSpacer` 획을 따라 일정 간격으로 흑연 점을 찍는다
  - `PaperTexture` 이어 붙여도 이음매 없는 종이결 높이맵
  - `GraphiteRaster` 128px 타일 희소 래스터, `DabRasterizer` 점 하나를 래스터에 찍는다
  - `DraftingSheet` 종이 + 진행 중 획 + 예측 끝 + 실행 취소를 묶는다
  - `PendingSampleQueue` 펜슬 필압이 추정치에서 확정치로 바뀔 때까지 샘플을 임시로 그린다
  - `UndoHistory` 메모리 예산(256MB) 안에서 오래된 단계부터 잊는다
- `Jedo/Canvas/` — 펜슬 입력을 받는 UIKit 뷰. 종이는 512px 타일 이미지, 흑연은 바뀐 128px 타일만 다시 그린다.
- `Jedo/Shell/` — SwiftUI 셸: 연필꽂이, 실행 취소 버튼.
- `Tools/Specimen/render.sh` — 경도별 견본(필압 변화, 겹쳐 긋기, 눕혀 칠하기, 해칭, 세게 칠하기)을 맥에서 PNG로 렌더링한다. 아래 손잡이를 바꾼 뒤 결과를 바로 비교할 수 있다.
- `Tools/Icon/render.sh` — 같은 렌더러로 앱 아이콘을 그린다.

## 손맛 조율 손잡이

모두 눈으로 정한 첫 값이다. 실제 아이패드에서 써 보고 바꾼다.

| 무엇 | 어디 |
|---|---|
| 경도별 선 굵기·한 번 그을 때 농도·한계 농도·종이결 문턱·가장자리 번짐 | `GradeParameters.table` |
| 얼마나 세게 눌러야 최대 필압인지, 가벼운 필압 끌어올림 | `PressureCurve.fullScale`, `gamma` |
| 몇 도부터 심 옆면이 닿는지, 눕혔을 때 얼마나 넓고 옅어지는지 | `PencilDynamics`의 `tiltStartsBelow`, `fullSideBelow`, `sideStretch*`, `sideOpacityDrop`, `sideGrainLift` |
| 필압이 굵기를 얼마나 바꾸는지 | `PencilDynamics.pressureWidening` |
| 종이결의 크기·밀도 | `PaperTexture.bumpsPerPixel`, `bumpRadius` |
| 심 자체의 거친 정도, 종이결 경계의 부드러움 | `DabRasterizer.leadNoise`, `grainSoftness` |
| 흑연·종이 색 | `GraphiteShading` |

## 아직 안 한 것

- 마일스톤 2–4: 직선자, 컴퍼스, 삼각자, 원형자, 지우개.
- 렌더링은 Core Graphics(CPU)다. 맥 벤치마크에서 6B를 눕혀 빠르게 칠해도 프레임당 0.4ms 안쪽이라 Metal은 아직 필요 없다.
- 저장/공유, 커리큘럼, AI 기능은 이번 범위 밖이다.
