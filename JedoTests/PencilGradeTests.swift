import Testing
@testable import Jedo

struct PencilGradeTests {
    @Test func offersSevenGradesFromHBTo6B() {
        #expect(PencilGrade.allCases.map(\.label) == ["HB", "B", "2B", "3B", "4B", "5B", "6B"])
        #expect(PencilGrade.allCases.sorted() == PencilGrade.allCases)
        #expect(PencilGrade.hb.softness == 0)
        #expect(PencilGrade.b6.softness == 1)
    }

    @Test func everyGradeHasOneRowInTheTable() {
        #expect(GradeParameters.table.count == PencilGrade.allCases.count)
    }

    @Test func softerLeadsAreWiderDarkerAndFillMoreGrain() {
        for (harder, softer) in zip(PencilGrade.allCases, PencilGrade.allCases.dropFirst()) {
            let h = harder.parameters, s = softer.parameters
            #expect(s.lineWidthMM > h.lineWidthMM, "\(softer.label) should be wider than \(harder.label)")
            #expect(s.passOpacity > h.passOpacity, "\(softer.label) should lay more graphite than \(harder.label)")
            #expect(s.maxDensity > h.maxDensity, "\(softer.label) should get darker than \(harder.label)")
            #expect(s.grainThreshold < h.grainThreshold, "\(softer.label) should reach deeper into the grain")
        }
    }

    @Test func only6BFillsThePaperBlack() {
        #expect(PencilGrade.b6.parameters.maxDensity == 1)
        #expect(PencilGrade.hb.parameters.maxDensity <= 0.75, "HB burnishes long before black")
    }

    @Test func parametersStayInPhysicalRanges() {
        for grade in PencilGrade.allCases {
            let p = grade.parameters
            #expect((0.1...1.5).contains(p.lineWidthMM))
            #expect((0...1).contains(p.passOpacity))
            #expect((0...1).contains(p.maxDensity))
            #expect(p.maxDensity <= 1)
            #expect((0...1).contains(p.grainThreshold))
            #expect((0...1).contains(p.edgeSoftness))
        }
    }
}

struct PressureCurveTests {
    @Test func mapsForceIntoZeroToOne() {
        #expect(PressureCurve.pressure(force: 0, maximumPossibleForce: 4.17) == 0)
        #expect(PressureCurve.pressure(force: 4.17, maximumPossibleForce: 4.17) == 1)
        #expect(PressureCurve.pressure(force: 99, maximumPossibleForce: 4.17) == 1)
        #expect(PressureCurve.pressure(force: -1, maximumPossibleForce: 4.17) == 0)
    }

    @Test func isMonotonic() {
        var previous = -1.0
        for step in 0...100 {
            let p = PressureCurve.pressure(force: Double(step) / 100 * 4.17, maximumPossibleForce: 4.17)
            #expect(p >= previous)
            previous = p
        }
    }

    @Test func ordinaryDrawingForceLandsMidRange() {
        // Apple Pencil reports about 1 for an ordinary touch.
        let p = PressureCurve.pressure(force: 1, maximumPossibleForce: 4.17)
        #expect((0.3...0.7).contains(p))
    }

    @Test func survivesMissingMaximum() {
        #expect(PressureCurve.pressure(force: 1, maximumPossibleForce: 0) == 0)
        #expect(PressureCurve.pressure(force: .nan, maximumPossibleForce: 4.17) == 0)
    }
}
