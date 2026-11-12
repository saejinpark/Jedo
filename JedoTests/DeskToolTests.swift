import CoreGraphics
import Foundation
import Testing
@testable import Jedo

private let ppmm = 10.0

private func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: Double = 1e-6) -> Bool {
    hypot(Double(a.x - b.x), Double(a.y - b.y)) <= tolerance
}

struct ToolShapeTests {
    let square = ToolShape(pose: ToolPose(center: CGPoint(x: 100, y: 100), angle: 0),
                           outline: [CGPoint(x: -50, y: -50), CGPoint(x: 50, y: -50), CGPoint(x: 50, y: 50), CGPoint(x: -50, y: 50)],
                           holes: [ToolShape.Hole(center: .zero, radius: 20)])

    @Test func framesRoundTrip() {
        let turned = ToolShape(pose: ToolPose(center: CGPoint(x: 7, y: -3), angle: 1.1), outline: square.outline)
        let p = CGPoint(x: 31, y: 44)
        #expect(near(turned.world(turned.local(p)), p))
    }

    @Test func holesAreOpenPaper() {
        #expect(square.covers(CGPoint(x: 140, y: 100)))
        #expect(!square.covers(CGPoint(x: 110, y: 100)), "inside the hole")
        #expect(!square.covers(CGPoint(x: 160, y: 100)), "outside the outline")
        #expect(square.outlineContains(CGPoint(x: 110, y: 100)))
    }

    @Test func sideContactsMeasureOutward() {
        // Side 1 runs down the right, x = 150.
        let c = square.contact(.side(1), at: CGPoint(x: 156, y: 120), offset: 2)
        #expect(abs(c.distance - 6) < 1e-9)
        #expect(c.alongside)
        #expect(near(c.point, CGPoint(x: 152, y: 120)))
        #expect(!square.contact(.side(1), at: CGPoint(x: 156, y: 170), offset: 2).alongside)
    }

    @Test func holeContactsSitInsideTheRim() {
        let c = square.contact(.hole(0), at: CGPoint(x: 115, y: 100), offset: 2)
        #expect(abs(c.distance - 5) < 1e-9)
        #expect(near(c.point, CGPoint(x: 118, y: 100)))
    }
}

struct SetSquareTests {
    func angles(_ kind: ToolKind) -> [Double] {
        let c = SetSquare.cornersMM(kind)
        return c.indices.map { i in
            let a = c[i], b = c[(i + 1) % 3], d = c[(i + 2) % 3]
            let u = (Double(b.x - a.x), Double(b.y - a.y)), v = (Double(d.x - a.x), Double(d.y - a.y))
            return acos((u.0 * v.0 + u.1 * v.1) / (hypot(u.0, u.1) * hypot(v.0, v.1))) * 180 / .pi
        }
    }

    @Test func fortyFiveHasARightAngleAndTwoFortyFives() {
        let a = angles(.setSquare45)
        #expect(abs(a[0] - 90) < 1e-9 && abs(a[1] - 45) < 1e-9 && abs(a[2] - 45) < 1e-9)
    }

    @Test func thirtySixtyHasThirtyAndSixty() {
        let a = angles(.setSquare60)
        #expect(abs(a[0] - 90) < 1e-9 && abs(a[1] - 30) < 1e-9 && abs(a[2] - 60) < 1e-9)
    }

    @Test func turnsAboutItsMiddle() {
        let c = SetSquare.cornersMM(.setSquare60)
        let mean = CGPoint(x: c.reduce(0) { $0 + Double($1.x) } / 3, y: c.reduce(0) { $0 + Double($1.y) } / 3)
        #expect(near(mean, .zero, 1e-9))
    }

    @Test func aLineAlongTheHypotenuseFollowsIt() {
        let tool = DeskTool(kind: .setSquare45, pose: ToolPose(center: CGPoint(x: 1000, y: 1000), angle: 0))
        let shape = tool.shape(pixelsPerMillimeter: ppmm)
        var g = EdgeGuide(style: .standard, pixelsPerMillimeter: ppmm, contactOffset: 2)
        // Walk along the hypotenuse, wobbling 5–15 px outside it.
        let corners = SetSquare.cornersMM(.setSquare45).map { shape.world($0.scaled(ppmm)) }
        let a = corners[1], b = corners[2]
        let len = hypot(Double(b.x - a.x), Double(b.y - a.y))
        let normal = (x: Double(b.y - a.y) / len, y: -Double(b.x - a.x) / len) // outward for this winding
        var out: [CGPoint] = []
        for i in 1..<20 {
            let t = Double(i) / 20, wobble = 5 + Double(i % 3) * 5
            let p = CGPoint(x: Double(a.x) + Double(b.x - a.x) * t + normal.x * wobble,
                            y: Double(a.y) + Double(b.y - a.y) * t + normal.y * wobble)
            out.append(g.guide(StrokeSample(location: p), tools: [shape]).location)
        }
        for p in out {
            let c = shape.contact(.side(1), at: p, offset: 0)
            #expect(abs(c.distance - 2) < 1e-6, "2 px outside the hypotenuse")
        }
    }
}

struct CircleTemplateTests {
    @Test func holesFitInsideTheSheetWithoutTouching() {
        let holes = CircleTemplate.holes
        let w = CircleTemplate.widthMM / 2, h = CircleTemplate.heightMM / 2
        for hole in holes {
            let r = CircleTemplate.holeRadiusMM(hole.diameter)
            #expect(abs(Double(hole.center.x)) + r < w - 2)
            #expect(abs(Double(hole.center.y)) + r < h - 2)
        }
        for i in holes.indices { for j in holes.indices where j > i {
            let d = hypot(Double(holes[i].center.x - holes[j].center.x), Double(holes[i].center.y - holes[j].center.y))
            #expect(d > CircleTemplate.holeRadiusMM(holes[i].diameter) + CircleTemplate.holeRadiusMM(holes[j].diameter) + 1)
        } }
    }

    @Test func aLeadRunRoundAHoleDrawsTheMarkedSize() {
        let tool = DeskTool(kind: .circleTemplate, pose: ToolPose(center: CGPoint(x: 1000, y: 1000), angle: 0.3))
        let shape = tool.shape(pixelsPerMillimeter: ppmm)
        let index = CircleTemplate.holes.firstIndex { $0.diameter == 20 }!
        let center = shape.world(CircleTemplate.holes[index].center.scaled(ppmm))
        let lineWidth = 0.5 * ppmm
        var g = EdgeGuide(style: .standard, pixelsPerMillimeter: ppmm, contactOffset: lineWidth / 2)
        var radii: [Double] = []
        for i in 0..<36 {
            let a = Double(i) * .pi / 18, r = 92.0 + Double(i % 4) * 3 // the pencil wanders 0.5–1.7 mm inside the rim
            let p = CGPoint(x: Double(center.x) + cos(a) * r, y: Double(center.y) + sin(a) * r)
            let out = g.guide(StrokeSample(location: p), tools: [shape]).location
            radii.append(hypot(Double(out.x - center.x), Double(out.y - center.y)))
        }
        // Lead centre at 10 mm + 0.25 mm allowance − half the line: the line's middle near 10 mm.
        #expect(radii.allSatisfy { abs($0 - (100 + 2.5 - lineWidth / 2)) < 1e-6 })
    }

    @Test func thePencilCannotReachPaperThroughThePlastic() {
        let shape = DeskTool(kind: .circleTemplate, pose: ToolPose(center: CGPoint(x: 1000, y: 1000), angle: 0))
            .shape(pixelsPerMillimeter: ppmm)
        var g = EdgeGuide(style: .standard, pixelsPerMillimeter: ppmm, contactOffset: 2)
        let path = (0..<40).map { CGPoint(x: 300 + Double($0) * 35, y: 1000 + sin(Double($0)) * 200) }
        for p in path {
            #expect(!shape.covers(g.guide(StrokeSample(location: p), tools: [shape]).location))
        }
    }
}

struct EdgeGuideWithSeveralToolsTests {
    @Test func takesToTheNearerToolsEdge() {
        let ruler = Ruler(pose: ToolPose(center: CGPoint(x: 1000, y: 1000), angle: 0), length: 2000, width: 300).shape
        let other = Ruler(pose: ToolPose(center: CGPoint(x: 1000, y: 680), angle: 0), length: 2000, width: 300).shape
        // Gap between them runs from y = 830 to 850.
        var g = EdgeGuide(style: .standard, pixelsPerMillimeter: ppmm, contactOffset: 2)
        let out = g.guide(StrokeSample(location: CGPoint(x: 500, y: 846)), tools: [ruler, other])
        #expect(out.location == CGPoint(x: 500, y: 848))
        #expect(g.attached?.tool == 0)
    }
}

struct RubTrackerTests {
    func rub(_ xs: [Double]) -> [StrokeSample] {
        var t = RubTracker(pixelsPerMillimeter: ppmm)
        return xs.map { t.track(StrokeSample(location: CGPoint(x: $0, y: 0))) }
    }

    @Test func oneWayIsOnePass() {
        #expect(!rub(Array(stride(from: 0.0, through: 300, by: 5))).contains { $0.beginsPass })
    }

    @Test func backAndForthStartsAPassAtEachTurn() {
        let there = Array(stride(from: 0.0, through: 200, by: 5))
        let back = Array(stride(from: 200.0, through: 0, by: -5))
        let out = rub(there + back + there)
        #expect(out.filter(\.beginsPass).count == 2)
    }

    @Test func jitterIsNotARub() {
        let out = rub((0..<100).map { 100 + sin(Double($0)) * 5 })
        #expect(!out.contains { $0.beginsPass })
    }
}

struct ErasingTests {
    static let paper = PaperTexture(size: 64, seed: 3)

    func sheetWithALine() -> DraftingSheet {
        let sheet = DraftingSheet(width: 300, height: 200, pixelsPerMillimeter: ppmm, paper: Self.paper)
        let line = (0...40).map { StrokeSample(location: CGPoint(x: 20 + Double($0) * 6.5, y: 100), pressure: 0.8) }
        sheet.beginStroke(grade: .b4, at: line[0])
        sheet.extendStroke(with: Array(line.dropFirst()), predicted: [])
        sheet.endStroke()
        return sheet
    }

    func ink(_ sheet: DraftingSheet, _ xs: Range<Int> = 0..<300) -> Float {
        var total: Float = 0
        for y in 90..<110 { for x in xs { total += sheet.graphite.value(x: x, y: y) } }
        return total
    }

    func rub(_ sheet: DraftingSheet, times: Int, pressure: Double = 0.5) {
        var tracker = RubTracker(pixelsPerMillimeter: ppmm)
        var samples: [StrokeSample] = []
        for i in 0..<times {
            let xs = Array(stride(from: 100.0, through: 200, by: 4))
            for x in (i % 2 == 0 ? xs : xs.reversed()) {
                samples.append(tracker.track(StrokeSample(location: CGPoint(x: x, y: 100), pressure: pressure)))
            }
        }
        sheet.beginErasing()
        sheet.extendStroke(with: samples, predicted: [])
        sheet.endStroke()
    }

    @Test func rubbingLiftsGraphiteOnlyWhereTheEraserWent() {
        let sheet = sheetWithALine()
        let left = ink(sheet, 20..<70), middle = ink(sheet, 120..<180)
        rub(sheet, times: 1)
        #expect(ink(sheet, 20..<70) == left, "untouched beyond the rub")
        #expect(ink(sheet, 120..<180) < middle * 0.85)
    }

    @Test func moreRubsTakeOffMore() {
        let once = sheetWithALine(), often = sheetWithALine()
        rub(once, times: 1)
        rub(often, times: 6)
        #expect(ink(often, 120..<180) < ink(once, 120..<180) * 0.5)
    }

    @Test func pressingHarderTakesOffMore() {
        let light = sheetWithALine(), firm = sheetWithALine()
        rub(light, times: 1, pressure: 0.1)
        rub(firm, times: 1, pressure: 1)
        #expect(ink(firm, 120..<180) < ink(light, 120..<180))
    }

    @Test func erasingUndoesAsOneStep() {
        let sheet = sheetWithALine()
        let before = sheet.graphite.tiles
        rub(sheet, times: 4)
        #expect(sheet.graphite.tiles != before)
        #expect(sheet.undo())
        #expect(sheet.graphite.tiles == before)
    }

    @Test func erasingBlankPaperLeavesItBlank() {
        let sheet = DraftingSheet(width: 300, height: 200, pixelsPerMillimeter: ppmm, paper: Self.paper)
        rub(sheet, times: 3)
        #expect(ink(sheet) == 0)
    }

    @Test func theEraserShowsWhileRubbing() {
        let sheet = sheetWithALine()
        let before = sheet.displayedDensity(x: 150, y: 100)
        sheet.beginErasing()
        sheet.extendStroke(with: [StrokeSample(location: CGPoint(x: 140, y: 100), pressure: 1),
                                  StrokeSample(location: CGPoint(x: 160, y: 100), pressure: 1)], predicted: [])
        #expect(sheet.displayedDensity(x: 150, y: 100) < before)
        sheet.cancelStroke()
        #expect(sheet.displayedDensity(x: 150, y: 100) == before)
    }
}
