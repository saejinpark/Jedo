import CoreGraphics
import Testing
@testable import Jedo

struct ShellLayoutTests {
    @Test func rightHandedPutsThePencilTopRightAndTheOffHandBottomLeft() {
        let layout = ShellLayout.standard(leftHanded: false)
        #expect(layout.slot(of: .pencil) == .topTrailing)
        #expect(layout.slot(of: .history) == .bottomLeading)
        #expect(layout.groups(in: .bottomLeading).first == .history)
        #expect(!layout.mapOnTrailing)
        #expect(layout.isComplete)
    }

    @Test func leftHandedIsTheMirror() {
        let layout = ShellLayout.standard(leftHanded: true)
        #expect(layout.slot(of: .pencil) == .topLeading)
        #expect(layout.slot(of: .desk) == .bottomTrailing)
        #expect(layout.mapOnTrailing)
        #expect(ShellLayout.standard(leftHanded: false).mirrored == layout)
    }

    @Test func aMovedGroupLeavesItsPlaceAndJoinsTheEndOfTheNew() {
        var layout = ShellLayout.standard(leftHanded: false)
        layout.move(.history, to: .bottomTrailing)
        layout.move(.desk, to: .bottomTrailing)
        #expect(layout.groups(in: .bottomTrailing) == [.history, .desk])
        #expect(!layout.groups(in: .bottomLeading).contains(.history))
        #expect(layout.isComplete)
        layout.move(.history, to: .bottomTrailing)
        #expect(layout.groups(in: .bottomTrailing) == [.desk, .history])
    }

    @Test func aDropFindsTheNearestPlace() {
        let size = CGSize(width: 900, height: 1200)
        #expect(ShellLayout.Slot.at(CGPoint(x: 10, y: 10), in: size) == .topLeading)
        #expect(ShellLayout.Slot.at(CGPoint(x: 450, y: 1100), in: size) == .bottom)
        #expect(ShellLayout.Slot.at(CGPoint(x: 880, y: 700), in: size) == .bottomTrailing)
    }

    @Test func itIsRememberedAndABrokenRecordIsRefused() {
        var layout = ShellLayout.standard(leftHanded: true)
        layout.move(.view, to: .top)
        #expect(ShellLayout(encoded: layout.encoded) == layout)
        #expect(ShellLayout(encoded: "") == nil)
        #expect(ShellLayout(encoded: #"{"leftHanded":false,"slots":[]}"#) == nil)
    }

    @Test func theMapGoesToTheEmptierTopCorner() {
        var layout = ShellLayout.standard(leftHanded: false)
        layout.move(.desk, to: .topLeading)
        layout.move(.hand, to: .topLeading)
        layout.move(.sheets, to: .topLeading)
        #expect(layout.mapOnTrailing)
    }
}
