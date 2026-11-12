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

struct MechanicalPencilTests {
    let ppmm = 264.0 / 25.4

    func shape(_ grade: PencilGrade = .hb, _ instrument: Instrument, pressure: Double = 0.5, altitudeDegrees: Double = 90) -> DabShape {
        PencilDynamics(grade: grade, pixelsPerMillimeter: ppmm, instrument: instrument).shape(for: StrokeSample(
            location: .zero, pressure: pressure, altitude: altitudeDegrees * .pi / 180))
    }

    @Test func theLeadSetsTheWidthWhateverTheGrade() {
        for size in LeadSize.allCases {
            let hard = shape(.h2, .mechanical(size)).radiusAcross * 2 / ppmm
            let soft = shape(.b4, .mechanical(size)).radiusAcross * 2 / ppmm
            #expect(abs(hard - size.diameterMM) < size.diameterMM * 0.1)
            #expect(soft > hard && soft < size.diameterMM * 1.15, "soft leads smear only a little wider")
        }
    }

    @Test func gradeStillSetsTheDarkness() {
        #expect(shape(.b4, .mechanical(.mm05)).opacity > shape(.h2, .mechanical(.mm05)).opacity * 2)
    }

    @Test func itCannotBeLaidOnItsSide() {
        let upright = shape(.b2, .mechanical(.mm05), altitudeDegrees: 60)
        let low = shape(.b2, .mechanical(.mm05), altitudeDegrees: 15)
        #expect(low.radiusAlong < upright.radiusAlong * 1.5)
        // The wood pencil still shades a broad patch.
        let wood = shape(.b2, .wood, altitudeDegrees: 15)
        #expect(wood.radiusAlong > low.radiusAlong * 3)
    }

    @Test func pressureBarelyWidensTheLead() {
        let light = shape(.hb, .mechanical(.mm05), pressure: 0.1).radiusAcross
        let hard = shape(.hb, .mechanical(.mm05), pressure: 1).radiusAcross
        #expect(hard / light < 1.2)
    }
}
