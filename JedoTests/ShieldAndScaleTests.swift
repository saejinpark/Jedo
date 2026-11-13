import CoreGraphics
import Testing
@testable import Jedo

struct ErasingShieldTests {
    private func square(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
    }

    @Test func underThePlateOnlyTheOpeningsAreReached() {
        let shield = StrokeMask.Shield(outline: square(0, 0, 100, 100), openings: [square(40, 40, 60, 60)])
        let mask = StrokeMask(inside: [], outside: [], shields: [shield])
        #expect(mask.contains(CGPoint(x: 50, y: 50)))
        #expect(!mask.contains(CGPoint(x: 20, y: 20)))
        #expect(mask.contains(CGPoint(x: 150, y: 20)))
        #expect(mask.coverage(PixelRect(minX: 10, minY: 10, maxX: 20, maxY: 20)) == .none)
        #expect(mask.coverage(PixelRect(minX: 45, minY: 45, maxX: 55, maxY: 55)) == .all)
        #expect(mask.coverage(PixelRect(minX: 30, minY: 45, maxX: 55, maxY: 55)) == .part)
    }

    @Test func erasingThroughTheShieldLeavesTheLineBesideTheSlot() {
        let sheet = DraftingSheet(width: 200, height: 100, pixelsPerMillimeter: 10)
        sheet.beginStroke(grade: .b6, instrument: .wood)
        sheet.extendStroke(with: stride(from: 10.0, through: 190, by: 2).map {
            StrokeSample(location: CGPoint(x: $0, y: 50), pressure: 1, altitude: .pi / 2, azimuth: 0)
        }, predicted: [])
        sheet.endStroke()
        let shield = StrokeMask.Shield(outline: square(0, 0, 200, 100), openings: [square(80, 30, 120, 70)])
        sheet.beginErasing(mask: StrokeMask(inside: [], outside: [], shields: [shield]), kind: .electric)
        sheet.extendStroke(with: stride(from: 10.0, through: 190, by: 2).map {
            StrokeSample(location: CGPoint(x: $0, y: 50), pressure: 1, altitude: .pi / 2, azimuth: 0)
        }, predicted: [])
        sheet.endStroke()
        #expect(sheet.graphite.value(x: 100, y: 50) < 0.1)
        #expect(sheet.graphite.value(x: 40, y: 50) > 0.3)
    }

    @Test func theShieldHasItsOpeningsInsideThePlate() {
        let size = ShapeTemplate.size(.erasingShield)
        let cuts = ShapeTemplate.cuts(.erasingShield)
        #expect(cuts.count >= 10)
        for cut in cuts {
            for p in cut.outline {
                #expect(abs(p.x) < size.width / 2 - 2 && abs(p.y) < size.height / 2 - 2)
            }
        }
    }
}

struct ScaleRuleTests {
    @Test func eachFaceCarriesTwoScales() {
        #expect(ScaleRule.faces.count == 3)
        #expect(ScaleRule.faceName(0) == "1:100 · 1:200")
        #expect(Set(ScaleRule.faces.flatMap { [$0.upper, $0.lower] }) == [100, 200, 300, 400, 500, 600])
    }

    @Test func itGuidesLikeAStraightRule() {
        let tool = DeskTool(kind: .scaleRule, pose: ToolPose(center: CGPoint(x: 500, y: 500), angle: 0), face: 2)
        let shape = tool.shape(pixelsPerMillimeter: 10)
        let xs = shape.outline.map(\.x), ys = shape.outline.map(\.y)
        #expect(abs(Double(xs.max()! - xs.min()!) - ScaleRule.lengthMM * 10) < 1e-6, "\(xs) \(ys)")
        #expect(abs(Double(ys.max()! - ys.min()!) - ScaleRule.widthMM * 10) < 1e-6, "\(ys)")
    }
}
