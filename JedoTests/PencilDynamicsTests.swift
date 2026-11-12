import CoreGraphics
import Testing
@testable import Jedo

struct PencilDynamicsTests {
    let ppmm = 264.0 / 25.4

    func shape(_ grade: PencilGrade = .b2, pressure: Double = 0.5, altitudeDegrees: Double = 90, azimuth: Double = 0) -> DabShape {
        PencilDynamics(grade: grade, pixelsPerMillimeter: ppmm).shape(for: StrokeSample(
            location: .zero, pressure: pressure, altitude: altitudeDegrees * .pi / 180, azimuth: azimuth))
    }

    @Test func mediumPressureUprightMatchesTheGradesLineWidth() {
        for grade in PencilGrade.allCases {
            let s = shape(grade)
            let widthMM = s.radiusAcross * 2 / ppmm
            #expect(abs(widthMM - grade.parameters.lineWidthMM) < 0.001)
            #expect(s.radiusAlong == s.radiusAcross, "an upright point leaves a round mark")
        }
    }

    @Test func pressingHarderWidensAndDarkens() {
        var last = shape(pressure: 0)
        for step in 1...10 {
            let next = shape(pressure: Double(step) / 10)
            #expect(next.radiusAcross > last.radiusAcross)
            #expect(next.opacity >= last.opacity)
            #expect(next.grainThreshold <= last.grainThreshold, "pressure pushes graphite into the valleys")
            last = next
        }
    }

    @Test func theLightestTouchStillLeavesAFaintMark() {
        let s = shape(.hb, pressure: 0)
        #expect(s.opacity > 0)
        #expect(s.opacity < 0.15)
        #expect(s.minRadius >= PencilDynamics.minimumRadiusPixels)
    }

    @Test func ordinaryWritingAngleDoesNotChangeTheLine() {
        let upright = shape(altitudeDegrees: 90)
        let held = shape(altitudeDegrees: 55)
        #expect(held == upright)
    }

    @Test func tiltingLaysAWideLightPatch() {
        let tip = shape(altitudeDegrees: 60)
        let side = shape(altitudeDegrees: 15)
        #expect(side.radiusAlong > tip.radiusAlong * 5)
        #expect(side.radiusAcross > tip.radiusAcross * 2)
        #expect(side.radiusAlong > side.radiusAcross, "the patch stretches the way the pencil leans")
        #expect(side.opacity < tip.opacity)
        #expect(side.grainThreshold > tip.grainThreshold, "the side of the lead skims the tooth")
    }

    @Test func tiltGrowsSteadily() {
        var last = shape(altitudeDegrees: 90)
        for degrees in stride(from: 85.0, through: 0, by: -5) {
            let next = shape(altitudeDegrees: degrees)
            #expect(next.radiusAlong >= last.radiusAlong)
            #expect(next.opacity <= last.opacity)
            last = next
        }
    }

    @Test func patchFollowsTheAzimuth() {
        #expect(shape(altitudeDegrees: 20, azimuth: 1.2).angle == 1.2)
    }

    @Test func badReadingsDoNotProduceNaN() {
        let dynamics = PencilDynamics(grade: .b4, pixelsPerMillimeter: ppmm)
        for sample in [
            StrokeSample(location: .zero, pressure: .nan, altitude: .nan, azimuth: .nan),
            StrokeSample(location: .zero, pressure: 7, altitude: -3, azimuth: 100),
            StrokeSample(location: .zero, pressure: -1, altitude: 9, azimuth: -100),
        ] {
            let s = dynamics.shape(for: sample)
            for value in [s.radiusAlong, s.radiusAcross, s.angle, s.opacity, s.grainThreshold, s.edgeSoftness] {
                #expect(value.isFinite)
            }
            #expect((0...1).contains(s.opacity))
            #expect(dynamics.spacing(for: s) > 0)
        }
    }

    @Test func spacingIsSmallAgainstTheMark() {
        let dynamics = PencilDynamics(grade: .hb, pixelsPerMillimeter: ppmm)
        for pressure in [0.0, 0.5, 1.0] {
            let s = dynamics.shape(for: StrokeSample(location: .zero, pressure: pressure))
            #expect(dynamics.spacing(for: s) <= s.minRadius * 0.5 + 0.35)
        }
    }
}

struct LeadPointTests {
    @Test func drawingWearsThePointAndSharpeningRestoresIt() {
        var lead = LeadPoint()
        #expect(lead.bluntness() == 0)
        // A few A3-wide lines of HB, without turning the pencil.
        for _ in 0..<5 { lead.draw(300, pressure: 0.5, grade: .hb) }
        #expect(lead.bluntness() > 0.3, "the line has visibly thickened (about 1.9x)")
        #expect(lead.bluntness() < 0.9, "but is not yet worn flat")
        lead.sharpen()
        #expect(lead.bluntness() == 0)
    }

    @Test func softLeadsWearFasterThanHardOnes() {
        var soft = LeadPoint(), hard = LeadPoint()
        soft.draw(600, pressure: 0.5, grade: .b4)
        hard.draw(600, pressure: 0.5, grade: .h2)
        #expect(soft.bluntness() > hard.bluntness() * 3)
    }

    @Test func turningThePencilKeepsTheLineFine() {
        var still = LeadPoint(), turning = LeadPoint()
        for _ in 0..<12 {
            still.draw(150, pressure: 0.5, grade: .hb)
            turning.draw(150, pressure: 0.5, grade: .hb)
            turning.turn()
        }
        #expect(turning.bluntness() < still.bluntness() * 0.5, "the wear spread round the cone")
    }

    @Test func oneLongShadingStrokeDoesNotWearItFlat() {
        // What happened on the iPad: a 1.5 m scribble of 4B.
        var lead = LeadPoint()
        for _ in 0..<150 { lead.draw(10, pressure: 0.6, grade: .b4) }
        #expect(lead.bluntness() < 0.95)
        // And the change along the way is gradual, not all at the start.
        var early = LeadPoint()
        for _ in 0..<10 { early.draw(10, pressure: 0.6, grade: .b4) }
        #expect(early.bluntness() < 0.25)
    }

    @Test func aTurnBringsAFresherSideDown() {
        var lead = LeadPoint()
        for _ in 0..<4 { lead.draw(300, pressure: 0.5, grade: .hb) }
        let worn = lead.bluntness()
        lead.turn()
        #expect(lead.bluntness() < worn * 0.6, "the next side is much less worn")
        // Turning also counts on top of a sensed roll.
        var rolled = LeadPoint()
        rolled.draw(1200, pressure: 0.5, grade: .hb, roll: 0.1)
        let before = rolled.bluntness(roll: 0.1)
        rolled.turn()
        #expect(rolled.bluntness(roll: 0.1) < before)
    }

    @Test func barrelRollPicksTheSide() {
        var lead = LeadPoint()
        lead.draw(1200, pressure: 0.5, grade: .hb, roll: 0.1)
        #expect(lead.bluntness(roll: 0.1) > 0.25)
        #expect(lead.bluntness(roll: .pi) < 0.01, "the far side is still sharp")
        #expect(lead.side(roll: -0.1) == LeadPoint.sides - 1)
    }

    @Test func aBluntPointLaysAWiderGreyerMark() {
        let dynamics = PencilDynamics(grade: .hb, pixelsPerMillimeter: 10)
        let sharp = dynamics.shape(for: StrokeSample(location: .zero))
        let blunt = dynamics.shape(for: StrokeSample(location: .zero, bluntness: 1))
        #expect(blunt.radiusAcross > sharp.radiusAcross * 3)
        #expect(blunt.opacity < sharp.opacity)
    }
}
