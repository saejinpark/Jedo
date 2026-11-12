import CoreGraphics
import Foundation
import Testing
@testable import Jedo

private let ppmm = 264.0 / 25.4

private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    hypot(Double(a.x - b.x), Double(a.y - b.y))
}

private func around(_ center: CGPoint, radius: Double, angle: Double) -> CGPoint {
    CGPoint(x: Double(center.x) + cos(angle) * radius, y: Double(center.y) + sin(angle) * radius)
}

struct CompassTests {
    let needle = CGPoint(x: 500, y: 500)

    @Test func thePencilsDistanceSetsTheSpread() {
        let compass = Compass(needle: needle)
        let spread = compass.spread(forPencilAt: CGPoint(x: 600, y: 500), keepsSpread: false, pixelsPerMillimeter: ppmm)
        #expect(spread == 100)
    }

    @Test func tooCloseOrTooFarTheCompassCannotReach() {
        let compass = Compass(needle: needle)
        let tooClose = CGPoint(x: Double(needle.x) + 1 * ppmm, y: Double(needle.y))
        let tooFar = CGPoint(x: Double(needle.x) + 160 * ppmm, y: Double(needle.y))
        #expect(compass.spread(forPencilAt: tooClose, keepsSpread: false, pixelsPerMillimeter: ppmm) == nil)
        #expect(compass.spread(forPencilAt: tooFar, keepsSpread: false, pixelsPerMillimeter: ppmm) == nil)
    }

    @Test func keptSpreadWinsNearItsCircleOnly() {
        let compass = Compass(needle: needle, spread: 200)
        let near = CGPoint(x: Double(needle.x), y: Double(needle.y) + 200 + 1.0 * ppmm)
        let far = CGPoint(x: Double(needle.x), y: Double(needle.y) + 200 + 3.0 * ppmm)
        #expect(compass.spread(forPencilAt: near, keepsSpread: true, pixelsPerMillimeter: ppmm) == 200)
        #expect(compass.spread(forPencilAt: near, keepsSpread: false, pixelsPerMillimeter: ppmm) != 200)
        let fresh = compass.spread(forPencilAt: far, keepsSpread: true, pixelsPerMillimeter: ppmm)
        #expect(abs(fresh! - (200 + 3 * ppmm)) < 1e-9)
    }

    @Test func theLeadRestsWhereItLastWas() {
        let compass = Compass(needle: needle, spread: 100, leadAngle: .pi / 2)
        #expect(distance(compass.lead!, CGPoint(x: 500, y: 600)) < 1e-9)
        #expect(Compass(needle: needle).lead == nil)
    }
}

struct ArcGuideTests {
    let center = CGPoint(x: 400, y: 400)

    func guide(radius: Double = 200) -> ArcGuide {
        ArcGuide(center: center, radius: radius, pixelsPerMillimeter: ppmm)
    }

    /// The pencil wandering on and off the circle, over a sweep of angles.
    func wobblyPath(from start: Double, to end: Double, radius: Double, count: Int = 120) -> [StrokeSample] {
        (0...count).map { i in
            let t = Double(i) / Double(count)
            let a = start + (end - start) * t
            let wobble = sin(t * 37) * 9 + cos(t * 11) * 6
            return StrokeSample(location: around(center, radius: radius + wobble, angle: a), pressure: 0.4 + 0.3 * t,
                                altitude: 0.4, azimuth: 1)
        }
    }

    @Test func everySampleLandsOnTheCircle() {
        var g = guide()
        let out = wobblyPath(from: 0, to: 2, radius: 200).flatMap { g.guide($0) }
        #expect(!out.isEmpty)
        #expect(out.allSatisfy { abs(distance($0.location, center) - 200) < 1e-6 })
    }

    @Test func theLeadFollowsThePencilsDirection() {
        var g = guide()
        _ = g.guide(StrokeSample(location: CGPoint(x: 700, y: 400)))
        let out = g.guide(StrokeSample(location: CGPoint(x: 400, y: 900)))
        #expect(distance(out.last!.location, CGPoint(x: 400, y: 600)) < 1e-6)
    }

    @Test func stepsAreShortEnoughThatTheChordFollowsTheArc() {
        var g = guide(radius: 300)
        _ = g.guide(StrokeSample(location: around(center, radius: 300, angle: 0)))
        let out = g.guide(StrokeSample(location: around(center, radius: 300, angle: 1.5)))
        #expect(out.count > 10, "a big swing is split up")
        var previous = around(center, radius: 300, angle: 0)
        for s in out {
            let mid = CGPoint(x: (previous.x + s.location.x) / 2, y: (previous.y + s.location.y) / 2)
            #expect(300 - distance(mid, center) <= ArcGuide.chordTolerance + 1e-9)
            previous = s.location
        }
    }

    @Test func swingsTheShortWayAcrossTheSeam() {
        var g = guide()
        _ = g.guide(StrokeSample(location: around(center, radius: 200, angle: .pi - 0.05)))
        let out = g.guide(StrokeSample(location: around(center, radius: 200, angle: -.pi + 0.05)))
        let arc = out.reduce((0.0, around(center, radius: 200, angle: .pi - 0.05))) { acc, s in
            (acc.0 + distance(acc.1, s.location), s.location)
        }.0
        #expect(arc < 0.11 * 200, "about 0.1 rad of arc, not most of a circle")
    }

    @Test func nearTheNeedleTheLeadWaits() {
        var g = guide()
        _ = g.guide(StrokeSample(location: CGPoint(x: 600, y: 400)))
        #expect(g.guide(StrokeSample(location: CGPoint(x: 410, y: 402))).isEmpty)
        #expect(g.lead.map { distance($0, CGPoint(x: 600, y: 400)) < 1e-9 } == true)
    }

    @Test func theLeadStandsUprightButKeepsThePencilsPressure() {
        var g = guide()
        let out = wobblyPath(from: 0, to: 1, radius: 200).flatMap { g.guide($0) }
        #expect(out.allSatisfy { $0.altitude == ArcGuide.leadAltitude })
        #expect(out.first!.pressure < out.last!.pressure)
    }

    @Test func oneWayRoundIsOnePass() {
        var g = guide()
        let out = wobblyPath(from: 0, to: 4, radius: 200).flatMap { g.guide($0) }
        #expect(!out.contains { $0.beginsPass })
        #expect(g.passes == 1)
    }

    @Test func comingRoundAgainStartsANewPassEachLap() {
        var g = guide()
        let out = wobblyPath(from: 0, to: 2 * .pi * 2.5, radius: 200, count: 600).flatMap { g.guide($0) }
        #expect(out.filter(\.beginsPass).count == 2)
        #expect(g.passes == 3)
    }

    @Test func turningBackStartsANewPass() {
        var g = guide()
        let there = wobblyPath(from: 0, to: 1, radius: 200)
        let back = wobblyPath(from: 1, to: 0.2, radius: 200)
        let out = (there + back).flatMap { g.guide($0) }
        #expect(out.filter(\.beginsPass).count == 1)
        // The new pass begins once the lead has come back about 1.5 mm.
        let turn = out.first(where: \.beginsPass)!
        let tip = around(center, radius: 200, angle: 1)
        #expect(abs(distance(turn.location, tip) - ArcGuide.reverseMM * ppmm) < 2)
    }

    @Test func aTrembleIsNotATurn() {
        var g = guide()
        var samples: [StrokeSample] = []
        for i in 0..<200 {
            let a = 0.5 + sin(Double(i) * 0.7) * (0.5 * ppmm / 200) // ±0.5 mm of arc
            samples.append(StrokeSample(location: around(center, radius: 200, angle: a)))
        }
        let out = samples.flatMap { g.guide($0) }
        #expect(!out.contains { $0.beginsPass })
    }

    @Test func aCopyRunsAheadWithoutMovingTheOriginal() {
        var g = guide()
        _ = g.guide(StrokeSample(location: CGPoint(x: 600, y: 400)))
        var lookahead = g
        _ = lookahead.guide(StrokeSample(location: CGPoint(x: 400, y: 600)))
        #expect(g.lead.map { distance($0, CGPoint(x: 600, y: 400)) < 1e-9 } == true)
    }
}

struct StrokeGuideTests {
    @Test func theEdgeGivesOneSampleForOne() {
        var guide = StrokeGuide.edge(EdgeGuide(style: .standard, pixelsPerMillimeter: ppmm, contactOffset: 0))
        let out = guide.guide(StrokeSample(location: CGPoint(x: 10, y: 10)), tools: [])
        #expect(out == [StrokeSample(location: CGPoint(x: 10, y: 10))])
    }

    @Test func theArcKeepsItsStateInsideTheEnum() {
        var guide = StrokeGuide.arc(ArcGuide(center: .zero, radius: 100, pixelsPerMillimeter: ppmm))
        _ = guide.guide(StrokeSample(location: CGPoint(x: 100, y: 0)), tools: [])
        let out = guide.guide(StrokeSample(location: CGPoint(x: 0, y: 300)), tools: [])
        #expect(out.count > 1)
        #expect(distance(out.last!.location, CGPoint(x: 0, y: 100)) < 1e-9)
        #expect(guide.arc?.lead != nil)
    }
}

struct LongPressTests {
    func press() -> LongPress<Int> { LongPress(duration: 0.4, slop: 10, tapDuration: 0.3) }

    @Test func aStillFingerIsDueOnceAfterTheDuration() {
        var lp = press()
        lp.begin(1, at: CGPoint(x: 5, y: 5), time: 10)
        #expect(lp.due(at: 10.3).isEmpty)
        let due = lp.due(at: 10.41)
        #expect(due.count == 1 && due[0].key == 1 && due[0].point == CGPoint(x: 5, y: 5))
        #expect(lp.due(at: 11).isEmpty, "reported once")
    }

    @Test func driftingTooFarIsNoLongPress() {
        var lp = press()
        lp.begin(1, at: .zero, time: 0)
        #expect(lp.move(1, to: CGPoint(x: 6, y: 6)) == false)
        #expect(lp.move(1, to: CGPoint(x: 12, y: 0)) == true)
        #expect(lp.move(1, to: CGPoint(x: 30, y: 0)) == false, "reported once")
        #expect(lp.due(at: 5).isEmpty)
        #expect(lp.end(1, time: 5) == .other)
    }

    @Test func aQuickStillTouchIsATap() {
        var lp = press()
        lp.begin(1, at: .zero, time: 0)
        #expect(lp.end(1, time: 0.2) == .tap)
        lp.begin(2, at: .zero, time: 0)
        #expect(lp.end(2, time: 0.35) == .other)
        #expect(lp.end(3, time: 1) == nil)
    }
}

struct MultiPassStrokeTests {
    static let paper = PaperTexture(size: 64, seed: 3)

    func sheet() -> DraftingSheet {
        DraftingSheet(width: 400, height: 300, pixelsPerMillimeter: ppmm, paper: Self.paper)
    }

    func samples(from a: CGPoint, to b: CGPoint, count: Int = 40) -> [StrokeSample] {
        (0...count).map { i in
            let t = Double(i) / Double(count)
            return StrokeSample(location: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), pressure: 0.5)
        }
    }

    func ink(_ sheet: DraftingSheet) -> Float {
        sheet.graphite.tiles.values.reduce(0) { $0 + $1.reduce(0, +) }
    }

    /// There and back along the same line in one stroke.
    func thereAndBack(_ sheet: DraftingSheet, newPass: Bool) {
        let there = samples(from: CGPoint(x: 50, y: 150), to: CGPoint(x: 350, y: 150))
        var back = samples(from: CGPoint(x: 350, y: 150), to: CGPoint(x: 50, y: 150))
        back[1].beginsPass = newPass
        sheet.beginStroke(grade: .b2, at: there[0])
        sheet.extendStroke(with: Array(there.dropFirst()) + Array(back.dropFirst()), predicted: [])
    }

    @Test func aSecondPassInOneStrokeDarkensTheLine() {
        let single = sheet(), double = sheet()
        thereAndBack(single, newPass: false)
        single.endStroke()
        thereAndBack(double, newPass: true)
        double.endStroke()
        #expect(ink(double) > ink(single) * 1.3)
    }

    @Test func allPassesUndoAsOneStep() {
        let s = sheet()
        thereAndBack(s, newPass: true)
        s.endStroke()
        #expect(s.undo())
        #expect(ink(s) == 0)
        #expect(!s.canUndo)
        #expect(s.redo())
        #expect(ink(s) > 0)
    }

    @Test func cancellingTakesBackPassesAlreadyLaid() {
        let s = sheet()
        thereAndBack(s, newPass: true)
        #expect(ink(s) > 0, "the first pass is already on the sheet")
        s.cancelStroke()
        #expect(ink(s) == 0)
        #expect(!s.canUndo)
    }

    @Test func passesDarkenWhatWasAlreadyThereOnlyOnce() {
        // Undoing a two-pass stroke drawn over an older line brings that line back exactly.
        let s = sheet()
        let old = samples(from: CGPoint(x: 200, y: 20), to: CGPoint(x: 200, y: 280))
        s.beginStroke(grade: .b, at: old[0])
        s.extendStroke(with: Array(old.dropFirst()), predicted: [])
        s.endStroke()
        let before = s.graphite.tiles
        thereAndBack(s, newPass: true)
        s.endStroke()
        s.undo()
        #expect(s.graphite.tiles == before)
    }
}
