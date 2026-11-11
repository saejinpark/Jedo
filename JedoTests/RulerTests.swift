import CoreGraphics
import Testing
@testable import Jedo

struct RulerTests {
    /// 200 px long, 30 px wide, lying flat, centred at (500, 500).
    let flat = Ruler(pose: RulerPose(center: CGPoint(x: 500, y: 500), angle: 0), length: 200, width: 30)

    @Test func localFrameRoundTrips() {
        let turned = Ruler(pose: RulerPose(center: CGPoint(x: 10, y: 20), angle: 0.7), length: 200, width: 30)
        let p = CGPoint(x: 83.5, y: -41.25)
        let (u, v) = turned.local(p)
        let back = turned.point(u: u, v: v)
        #expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)
    }

    @Test func knowsWhatIsUnderIt() {
        #expect(flat.contains(CGPoint(x: 500, y: 500)))
        #expect(flat.contains(CGPoint(x: 599, y: 514)))
        #expect(!flat.contains(CGPoint(x: 601, y: 500)))
        #expect(!flat.contains(CGPoint(x: 500, y: 516)))
        #expect(flat.contains(CGPoint(x: 500, y: 516), margin: 2))
    }

    @Test func upperEdgeIsAboveForAFlatRuler() {
        #expect(flat.pointAlong(.upper, u: 0, offset: 0) == CGPoint(x: 500, y: 485))
        #expect(flat.pointAlong(.lower, u: 50, offset: 2) == CGPoint(x: 550, y: 517))
        #expect(flat.outsideDistance(v: -20, from: .upper) == 5)
        #expect(flat.outsideDistance(v: 10, from: .lower) == -5)
    }

    @Test func edgesTurnWithTheRuler() {
        // Turned a quarter clockwise on screen: the upper edge now faces +x.
        let upright = Ruler(pose: RulerPose(center: .zero, angle: .pi / 2), length: 200, width: 30)
        let p = upright.pointAlong(.upper, u: 0, offset: 0)
        #expect(abs(p.x - 15) < 1e-9 && abs(p.y) < 1e-9)
    }
}

struct RigidMotionTests {
    let pose = RulerPose(center: CGPoint(x: 100, y: 100), angle: 0.3)

    @Test func oneFingerSlides() {
        let moved = RigidMotion.slide(pose, from: CGPoint(x: 90, y: 95), to: CGPoint(x: 130, y: 85))
        #expect(moved.center == CGPoint(x: 140, y: 90))
        #expect(moved.angle == 0.3)
    }

    @Test func twoFingersTurnAboutTheirMidpoint() {
        // Fingers either side of the centre turn a quarter: the centre stays, the angle turns.
        let moved = RigidMotion.slideAndTurn(pose,
            from: (CGPoint(x: 50, y: 100), CGPoint(x: 150, y: 100)),
            to: (CGPoint(x: 100, y: 50), CGPoint(x: 100, y: 150)))
        #expect(abs(moved.center.x - 100) < 1e-9 && abs(moved.center.y - 100) < 1e-9)
        #expect(abs(moved.angle - (0.3 + .pi / 2)) < 1e-9)
    }

    @Test func pointsUnderTheFingersStayUnderThem() {
        let ruler = Ruler(pose: pose, length: 300, width: 40)
        let a0 = CGPoint(x: 60, y: 90), b0 = CGPoint(x: 160, y: 120)
        let a1 = CGPoint(x: 80, y: 140), b1 = CGPoint(x: 150, y: 215)
        let gripA = ruler.local(a0), gripB = ruler.local(b0)
        let moved = Ruler(pose: RigidMotion.slideAndTurn(pose, from: (a0, b0), to: (a1, b1)), length: 300, width: 40)
        // The fingers moved apart a little, so a rigid ruler cannot follow both exactly;
        // each grip point stays within half that stretch of its finger.
        let stretch = abs(hypot(b1.x - a1.x, b1.y - a1.y) - hypot(b0.x - a0.x, b0.y - a0.y))
        let nowA = moved.point(u: gripA.u, v: gripA.v), nowB = moved.point(u: gripB.u, v: gripB.v)
        #expect(hypot(nowA.x - a1.x, nowA.y - a1.y) <= stretch / 2 + 1e-6)
        #expect(hypot(nowB.x - b1.x, nowB.y - b1.y) <= stretch / 2 + 1e-6)
    }

    @Test func turningTakesTheShortWay() {
        let start = RulerPose(center: .zero, angle: 0)
        let moved = RigidMotion.slideAndTurn(start,
            from: (CGPoint(x: 0, y: 0), CGPoint(x: -100, y: 1)),
            to: (CGPoint(x: 0, y: 0), CGPoint(x: -100, y: -1)))
        #expect(abs(moved.angle) < 0.05)
    }

    @Test func fingersOnTopOfEachOtherOnlySlide() {
        let moved = RigidMotion.slideAndTurn(pose,
            from: (CGPoint(x: 50, y: 50), CGPoint(x: 51, y: 50)),
            to: (CGPoint(x: 70, y: 50), CGPoint(x: 70, y: 51)))
        #expect(moved.angle == pose.angle)
        #expect(abs(moved.center.x - 119.5) < 1e-9)
    }
}

struct EdgeGuideTests {
    let ppmm = 10.0
    /// 2000 px long, 300 px wide, centred at (1000, 1000); upper edge at y = 850.
    let ruler = Ruler(pose: RulerPose(center: CGPoint(x: 1000, y: 1000), angle: 0), length: 2000, width: 300)

    func guide(_ style: EdgeGuideStyle) -> EdgeGuide {
        EdgeGuide(style: style, pixelsPerMillimeter: ppmm, contactOffset: 2)
    }

    func run(_ style: EdgeGuideStyle, _ points: [(Double, Double)]) -> [CGPoint] {
        var g = guide(style)
        return points.map { g.guide(StrokeSample(location: CGPoint(x: $0.0, y: $0.1)), ruler: ruler).location }
    }

    @Test func farFromTheRulerNothingChanges() {
        for style in EdgeGuideStyle.all {
            #expect(run(style, [(500, 600), (520, 610)]) == [CGPoint(x: 500, y: 600), CGPoint(x: 520, y: 610)])
        }
    }

    @Test func withoutARulerNothingChanges() {
        var g = guide(.stickUntilLift)
        let s = StrokeSample(location: CGPoint(x: 1000, y: 851))
        #expect(g.guide(s, ruler: nil) == s)
    }

    @Test func aWobblyLineNearTheEdgeComesOutStraight() {
        // 2.5 mm capture = 25 px. The hand wobbles between 10 and 20 px above the edge.
        let wobble: [(Double, Double)] = (0..<20).map { i in
            let x = Double(400 + i * 50)
            let y = 840.0 - Double(i % 3) * 5
            return (x, y)
        }
        for style in [EdgeGuideStyle.stickUntilLift, .letGo] {
            let ys = Set(run(style, wobble).map(\.y))
            #expect(ys == [848], "\(style.name): on the edge, lead centre 2 px outside it")
        }
    }

    @Test func theLeadNeverGoesUnderTheRuler() {
        for style in EdgeGuideStyle.all {
            let path = run(style, [(600, 840), (700, 870), (800, 900), (900, 860)])
            #expect(path.allSatisfy { !ruler.contains($0) }, "\(style.name)")
        }
    }

    @Test func pressingIntoTheRulerSlidesAlongTheEdgeYouCameFrom() {
        // Approaching from below and pushing past the centre line still stays on the lower edge.
        let path = run(.blockOnly, [(600, 1200), (650, 1140), (700, 990), (750, 960)])
        #expect(path[2] == CGPoint(x: 700, y: 1152))
        #expect(path[3] == CGPoint(x: 750, y: 1152))
    }

    @Test func blockOnlyDoesNotPull() {
        let path = run(.blockOnly, [(600, 840), (700, 845)])
        #expect(path == [CGPoint(x: 600, y: 840), CGPoint(x: 700, y: 845)])
    }

    @Test func letGoLeavesTheEdgeWhenPulledAway() {
        let path = run(.letGo, [(600, 840), (700, 830), (800, 800), (900, 760)])
        #expect(path[0].y == 848 && path[1].y == 848, "within 4 mm it stays on the edge")
        #expect(path[2] == CGPoint(x: 800, y: 800), "5 mm away it has let go")
        #expect(path[3] == CGPoint(x: 900, y: 760))
    }

    @Test func stickUntilLiftHoldsEvenWhenPulledAway() {
        let path = run(.stickUntilLift, [(600, 840), (700, 760), (800, 600)])
        #expect(path.allSatisfy { $0.y == 848 })
    }

    @Test func pastTheEndsTheRulerStopsGuiding() {
        let path = run(.stickUntilLift, [(1900, 840), (2100, 842)])
        #expect(path[0].y == 848)
        #expect(path[1] == CGPoint(x: 2100, y: 842))
    }

    @Test func aCopyRunsAheadWithoutChangingTheStroke() {
        var g = guide(.letGo)
        _ = g.guide(StrokeSample(location: CGPoint(x: 600, y: 840)), ruler: ruler)
        var lookahead = g
        _ = lookahead.guide(StrokeSample(location: CGPoint(x: 700, y: 500)), ruler: ruler)
        #expect(lookahead.attached == nil)
        #expect(g.attached == .upper)
    }

    @Test func followsATurnedRuler() {
        let turned = Ruler(pose: RulerPose(center: CGPoint(x: 0, y: 0), angle: .pi / 4), length: 2000, width: 300)
        var g = guide(.letGo)
        // A point 10 px outside the upper edge, half way along.
        let near = turned.pointAlong(.upper, u: 300, offset: 10)
        let out = g.guide(StrokeSample(location: near), ruler: turned).location
        let expected = turned.pointAlong(.upper, u: 300, offset: 2)
        #expect(abs(out.x - expected.x) < 1e-9 && abs(out.y - expected.y) < 1e-9)
    }
}
