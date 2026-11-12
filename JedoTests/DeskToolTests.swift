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

struct CurveToolTests {
    static let ppmm = 10.0

    func shape(_ kind: ToolKind, angle: Double = 0) -> ToolShape {
        DeskTool(kind: kind, pose: ToolPose(center: CGPoint(x: 2000, y: 2000), angle: angle)).shape(pixelsPerMillimeter: Self.ppmm)
    }

    /// Distance from `p` to the outline, outward positive.
    func distance(_ shape: ToolShape, _ p: CGPoint) -> Double {
        shape.contact(.boundary, at: p, offset: 0).distance
    }

    @Test func theBambooCurveIsStraightThenBendsOverItsLastSpan() {
        let spine = CurveTools.hipCurveProfile.spine(step: 1)
        let straightEnd = spine[Int(CurveTools.hipCurveStraightMM)]
        #expect(abs(straightEnd.angle - spine[0].angle) < 0.001, "the first 40 cm are straight")
        let total = abs(spine[spine.count - 1].angle - spine[0].angle)
        #expect(total > 35 * .pi / 180 && total < 45 * .pi / 180, "about 40° over the last 20 cm")
        #expect(CurveTools.hipCurveLengthMM >= 600)
    }

    @Test func curvedToolsGuideAsOneEdgePlusTheirSlots() {
        #expect(shape(.hipCurve).guidingEdges == [.boundary])
        #expect(shape(.frenchCurveA).guidingEdges == [.boundary, .cutout(0)])
        #expect(shape(.frenchCurveC).guidingEdges == [.boundary, .cutout(0), .cutout(1)])
        #expect(shape(.ruler).guidingEdges == [.side(0), .side(2)])
    }

    @Test func theSetHasFourDifferentCurves() {
        #expect(FrenchCurve.forms.map(\.kind) == ToolKind.frenchCurves)
        let turns = FrenchCurve.forms.map { form -> Double in
            let spine = form.profile.spine()
            return spine[spine.count - 1].angle - spine[0].angle
        }
        #expect(Set(turns.map { ($0 * 10).rounded() }).count == 4)
    }

    @Test func theSCurveBendsBothWays() {
        let spine = FrenchCurve.form(.frenchCurveB)!.profile.spine()
        let angles = spine.map(\.angle)
        let lowest = angles.min()!
        #expect(lowest < angles.first! - 0.1, "first it bends up")
        #expect(angles.last! > lowest + 0.5, "then back down, further")
    }

    @Test func theScrollTightensTowardItsTip() {
        // The bend grows steadily: the second half of the bend turns three times the first.
        let form = FrenchCurve.form(.frenchCurveA)!
        let spine = form.profile.spine()
        let bendStart = Int(35 / 0.5)
        let mid = (bendStart + spine.count - 1) / 2
        let first = abs(spine[mid].angle - spine[bendStart].angle)
        let second = abs(spine[spine.count - 1].angle - spine[mid].angle)
        #expect(abs(second / first - 3) < 0.1)
        #expect(spine[0].width > spine[spine.count - 1].width * 4)
    }

    @Test func everySlotIsOpenPaperThatGuides() {
        for kind in ToolKind.frenchCurves {
            let s = shape(kind)
            for (index, slot) in FrenchCurve.slots(kind).enumerated() {
                let rim = slot[slot.count / 4], opposite = slot[slot.count * 3 / 4]
                let middle = CGPoint(x: (rim.x + opposite.x) / 2, y: (rim.y + opposite.y) / 2)
                #expect(!s.covers(s.world(middle.scaled(Self.ppmm))), "the slot's middle is paper")
                // 1.5 mm in from the rim, toward the middle: within reach of the rim.
                let toward = (x: Double(middle.x - rim.x), y: Double(middle.y - rim.y))
                let len = hypot(toward.x, toward.y)
                let near = CGPoint(x: Double(rim.x) + toward.x / len * 1.5, y: Double(rim.y) + toward.y / len * 1.5)
                var g = EdgeGuide(style: .standard, pixelsPerMillimeter: Self.ppmm, contactOffset: 2)
                let out = g.guide(StrokeSample(location: s.world(near.scaled(Self.ppmm))), tools: [s]).location
                #expect(abs(s.contact(.cutout(index), at: out, offset: 0).distance - 2) < 0.05)
            }
        }
    }

    @Test func slotsSitInsideTheBody() {
        for kind in ToolKind.frenchCurves {
            let s = shape(kind)
            for slot in FrenchCurve.slots(kind) {
                for q in slot {
                    let p = s.world(q.scaled(Self.ppmm))
                    #expect(s.outlineContains(p))
                    #expect(abs(s.contact(.boundary, at: p, offset: 0).distance) > 2 * Self.ppmm, "at least 2 mm of plastic round a slot")
                }
            }
        }
    }

    @Test func aWobblyLineAlongEachFrenchCurveHugsItEverywhere() {
        for kind in ToolKind.frenchCurves {
            let s = shape(kind, angle: 0.4)
            var g = EdgeGuide(style: .standard, pixelsPerMillimeter: Self.ppmm, contactOffset: 3)
            let rim = FrenchCurve.outline(kind)
            var outs: [CGPoint] = []
            for (i, q) in rim.enumerated() where i < rim.count - 1 {
                let next = rim[i + 1]
                let dx = Double(next.x - q.x), dy = Double(next.y - q.y)
                let len = max(hypot(dx, dy), 1e-9)
                var normal = (x: dy / len, y: -dx / len)
                let probe = CGPoint(x: Double(q.x) + normal.x * 0.3, y: Double(q.y) + normal.y * 0.3).scaled(Self.ppmm)
                if s.outlineContains(s.world(probe)) { normal = (-normal.x, -normal.y) }
                let wobble = 0.5 + 1.5 * (0.5 + 0.5 * sin(Double(i) * 0.9))
                let p = CGPoint(x: Double(q.x) + normal.x * wobble, y: Double(q.y) + normal.y * wobble).scaled(Self.ppmm)
                outs.append(g.guide(StrokeSample(location: s.world(p)), tools: [s]).location)
            }
            for p in outs {
                #expect(abs(distance(s, p) - 3) < 0.05, "lead centre 3 px off the curve")
            }
        }
    }

    @Test func thePencilNeverGetsUnderTheBambooCurve() {
        let s = shape(.hipCurve, angle: -0.2)
        var g = EdgeGuide(style: .standard, pixelsPerMillimeter: Self.ppmm, contactOffset: 2)
        for i in 0..<200 {
            let p = CGPoint(x: -1000 + Double(i) * 30, y: 2000 + sin(Double(i) * 0.3) * 400)
            let out = g.guide(StrokeSample(location: p), tools: [s]).location
            #expect(!s.covers(out))
        }
    }

    @Test func bothLongEdgesOfTheBambooCurveGuide() {
        let s = shape(.hipCurve)
        let edges = CurveTools.hipCurveEdgesMM
        for edge in [edges.scale, edges.inner] {
            for index in [100, 260] {
                let q = edge[index], r = edge[index + 1]
                let dx = Double(r.x - q.x), dy = Double(r.y - q.y), len = hypot(dx, dy)
                var normal = (x: dy / len, y: -dx / len)
                if s.outlineContains(s.world(CGPoint(x: Double(q.x) + normal.x * 0.5, y: Double(q.y) + normal.y * 0.5).scaled(Self.ppmm))) {
                    normal = (-normal.x, -normal.y)
                }
                let p = s.world(CGPoint(x: Double(q.x) + normal.x * 1.5, y: Double(q.y) + normal.y * 1.5).scaled(Self.ppmm))
                var g = EdgeGuide(style: .standard, pixelsPerMillimeter: Self.ppmm, contactOffset: 2)
                let out = g.guide(StrokeSample(location: p), tools: [s]).location
                #expect(abs(distance(s, out) - 2) < 0.05)
            }
        }
    }

    @Test func curvedOutlinesDoNotCrossThemselves() {
        var outlines = [CurveTools.hipCurveMM]
        for kind in ToolKind.frenchCurves { outlines += [FrenchCurve.outline(kind)] + FrenchCurve.slots(kind) }
        for outline in outlines {
            let n = outline.count
            var crossings = 0
            for i in 0..<(n - 2) {
                let a = outline[i], b = outline[(i + 1) % n]
                for j in (i + 2)..<n where !(i == 0 && j == n - 1) {
                    let c = outline[j], d = outline[(j + 1) % n]
                    if segmentsCross(a, b, c, d) { crossings += 1 }
                }
            }
            #expect(crossings == 0)
        }
    }

    func segmentsCross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func orient(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Double {
            Double(q.x - p.x) * Double(r.y - p.y) - Double(q.y - p.y) * Double(r.x - p.x)
        }
        return orient(a, b, c) * orient(a, b, d) < 0 && orient(c, d, a) * orient(c, d, b) < 0
    }
}

struct ProtractorTests {
    static let ppmm = 10.0

    func shape(angle: Double = 0) -> ToolShape {
        DeskTool(kind: .protractor, pose: ToolPose(center: CGPoint(x: 1000, y: 1000), angle: angle)).shape(pixelsPerMillimeter: Self.ppmm)
    }

    @Test func turnsAboutTheCentreOfItsBaseLine() {
        let s = shape(angle: 0.7)
        #expect(s.world(.zero) == CGPoint(x: 1000, y: 1000))
        #expect(s.covers(CGPoint(x: 1000, y: 1000)))
    }

    @Test func aLineRoundTheArcFollowsIt() {
        let s = shape()
        var g = EdgeGuide(style: .standard, pixelsPerMillimeter: Self.ppmm, contactOffset: 2)
        let r = Protractor.radiusMM * Self.ppmm
        for i in 0...60 {
            let a = Double.pi * (0.2 + 0.6 * Double(i) / 60)
            let wobble = 8 + 6 * sin(Double(i))
            let p = CGPoint(x: 1000 + cos(a) * (r + wobble), y: 1000 - sin(a) * (r + wobble))
            let out = g.guide(StrokeSample(location: p), tools: [s]).location
            #expect(abs(hypot(Double(out.x) - 1000, Double(out.y) - 1000) - (r + 2)) < 0.05)
        }
    }

    @Test func theBaseIsAStraightEdge() {
        let s = shape()
        var g = EdgeGuide(style: .standard, pixelsPerMillimeter: Self.ppmm, contactOffset: 2)
        let base = 1000 + Protractor.baseMM * Self.ppmm
        for i in 0..<40 {
            let p = CGPoint(x: 600 + Double(i) * 20, y: base + 10 + Double(i % 3) * 4)
            let y = g.guide(StrokeSample(location: p), tools: [s]).location.y
            #expect(abs(y - (base + 2)) < 1e-6)
        }
    }

    @Test func degreesRunAnticlockwiseFromTheRight() {
        #expect(abs(Protractor.onArc(degree: 0).x - 60) < 1e-9)
        #expect(abs(Protractor.onArc(degree: 90).y + 60) < 1e-9)
        #expect(abs(Protractor.onArc(degree: 180).x + 60) < 1e-9)
    }
}

struct OverviewTests {
    @Test func aLineShowsInTheCellsItCrossesOnly() {
        let sheet = DraftingSheet(width: 1000, height: 1000, pixelsPerMillimeter: 10, paper: PaperTexture(size: 64, seed: 1))
        let line = (0...50).map { StrokeSample(location: CGPoint(x: 100 + Double($0) * 10, y: 250), pressure: 0.8) }
        sheet.beginStroke(grade: .b4, at: line[0])
        sheet.extendStroke(with: Array(line.dropFirst()), predicted: [])
        sheet.endStroke()
        let map = sheet.overview(size: 10)
        // Row 2 (y 200–300) from column 1 to 6 holds the line.
        for column in 1...5 { #expect(map[2 * 10 + column] > 0.2) }
        #expect(map[8 * 10 + 5] == 0)
        #expect(map[2 * 10 + 8] == 0)
    }

    @Test func blankPaperIsBlank() {
        let sheet = DraftingSheet(width: 500, height: 500, pixelsPerMillimeter: 10, paper: PaperTexture(size: 64, seed: 1))
        #expect(sheet.overview(size: 16).allSatisfy { $0 == 0 })
    }
}

struct ShapeTemplateTests {
    static let ppmm = 10.0
    static let kinds: [ToolKind] = [.ellipseTemplate, .squareTemplate, .hexTemplate]

    @Test func cutsFitInsideTheSheetWithoutTouching() {
        for kind in Self.kinds {
            let size = ShapeTemplate.size(kind)
            let cuts = ShapeTemplate.cuts(kind)
            #expect(cuts.count >= 10)
            #expect(size.width <= 165, "fits across an 11-inch screen held upright")
            for cut in cuts {
                for p in cut.outline {
                    #expect(abs(p.x) < size.width / 2 - 2 && abs(p.y) < size.height / 2 - 2)
                }
            }
            for i in cuts.indices { for j in cuts.indices where j > i {
                let a = cuts[i], b = cuts[j]
                let apartX = abs(a.center.x - b.center.x) - a.halfSize.width - b.halfSize.width
                let apartY = abs(a.center.y - b.center.y) - a.halfSize.height - b.halfSize.height
                #expect(max(apartX, apartY) > 1, "at least 1 mm of plastic between cuts")
            } }
        }
    }

    @Test func ellipsesAreIsometric() {
        for cut in ShapeTemplate.cuts(.ellipseTemplate) {
            let a = Double(cut.halfSize.width) - ShapeTemplate.leadAllowanceMM
            let b = Double(cut.halfSize.height) - ShapeTemplate.leadAllowanceMM
            #expect(abs(b / a - 0.577) < 0.001)
        }
    }

    @Test func aSquareCutGuidesTheLeadAlongItsSides() {
        let shape = DeskTool(kind: .squareTemplate, pose: ToolPose(center: CGPoint(x: 2000, y: 2000), angle: 0))
            .shape(pixelsPerMillimeter: Self.ppmm)
        let index = ShapeTemplate.cuts(.squareTemplate).firstIndex { $0.label == "20" }!
        let cut = ShapeTemplate.cuts(.squareTemplate)[index]
        // Run along the inside of the top side, 1–2 mm below it.
        let top = Double(cut.center.y - cut.halfSize.height)
        var g = EdgeGuide(style: .standard, pixelsPerMillimeter: Self.ppmm, contactOffset: 2)
        for i in 0..<20 {
            let x = Double(cut.center.x) - 7 + Double(i) * 0.7
            let p = shape.world(CGPoint(x: x, y: top + 1 + Double(i % 3) * 0.5).scaled(Self.ppmm))
            let out = g.guide(StrokeSample(location: p), tools: [shape]).location
            #expect(abs(shape.contact(.cutout(index), at: out, offset: 0).distance - 2) < 0.05)
            #expect(abs(Double(out.y) - (2000 + top * Self.ppmm + 2)) < 1e-6)
        }
    }

    @Test func cutsAreMadeLargerSoTheLineIsTheMarkedSize() {
        // A 20 mm square's sides sit 10.25 mm from its centre.
        let cut = ShapeTemplate.cuts(.squareTemplate).first { $0.label == "20" }!
        #expect(abs(Double(cut.halfSize.width) - 10.25) < 1e-9)
    }
}
