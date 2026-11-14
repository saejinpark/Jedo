import CoreGraphics
import SwiftUI
import Testing
@testable import Jedo

struct ShellLayoutTests {
    // An 11-inch iPad upright: about 15 by 22 squares.
    let columns = 15, rows = 22

    @Test func rightHandedPutsThePencilTopRightAndTheOffHandBottomLeft() {
        let cells = ShellLayout.standard(leftHanded: false).cells(columns: columns, rows: rows)
        #expect(cells[.pencil]!.x + cells[.pencil]!.w == columns && cells[.pencil]!.y == 0)
        #expect(cells[.view]!.x == 0 && cells[.view]!.y == 0)
        #expect(cells[.history]!.x == 0 && cells[.history]!.y == rows - 1)
        // The map stands on the bottom row, its stick under the other hand's thumb.
        #expect(cells[.map]!.x == 0 && cells[.map]!.y + cells[.map]!.h == rows - 1)
        #expect(ShellLayout.standard(leftHanded: false).isComplete)
    }

    @Test func turnedOnItsSideTheOtherHandsThingsShareOneRow() {
        let cells = ShellLayout.standard(leftHanded: false).cells(columns: 22, rows: 15)
        for group in [ShellLayout.Group.history, .hand, .sheets, .desk] { #expect(cells[group]!.y == 14) }
        #expect(cells[.papers]!.y == 13)
        // The drawing palm's corner stays clear.
        #expect(!cells.values.contains { $0.x + $0.w > 18 && $0.y + $0.h > 10 })
    }

    @Test func nothingOverlapsOnAnyIPad() {
        for (c, r) in [(15, 22), (22, 15), (13, 19), (19, 13), (19, 25), (25, 19)] {
            for left in [false, true] {
                let cells = Array(ShellLayout.standard(leftHanded: left).cells(columns: c, rows: r).values)
                for i in cells.indices {
                    for j in cells.indices where j > i { #expect(!cells[i].overlaps(cells[j]), "\(c)x\(r)") }
                    #expect(cells[i].x >= 0 && cells[i].x + cells[i].w <= c && cells[i].y + cells[i].h <= r)
                }
            }
        }
    }

    @Test func leftHandedIsTheMirror() {
        let cells = ShellLayout.standard(leftHanded: true).cells(columns: columns, rows: rows)
        #expect(cells[.pencil]!.x == 0)
        #expect(cells[.map]!.x + cells[.map]!.w == columns)
        #expect(ShellLayout.standard(leftHanded: false).mirrored == ShellLayout.standard(leftHanded: true))
    }

    @Test func aGroupDroppedOnFreeSquaresStaysByItsNearestCorner() {
        var layout = ShellLayout.standard(leftHanded: false)
        let placed = layout.place(.history, at: .init(x: 13, y: 10, w: 2, h: 1), columns: columns, rows: rows)
        #expect(placed)
        #expect(layout.cells(columns: columns, rows: rows)[.history] == .init(x: 13, y: 10, w: 2, h: 1))
        // Turned to landscape it keeps 0 squares from the right.
        let turned = layout.cells(columns: 22, rows: 15)[.history]!
        #expect(turned.x + turned.w == 22)
    }

    @Test func aGroupStandsUprightAndLiesDownAgain() {
        var layout = ShellLayout.standard(leftHanded: false)
        let lying = layout.cells(columns: 22, rows: 15)[.hand]!
        let stood = layout.turn(.hand, columns: 22, rows: 15)
        #expect(stood)
        let standing = layout.cells(columns: 22, rows: 15)[.hand]!
        #expect(standing.w == lying.h && standing.h == lying.w && layout.isUpright(.hand))
        // Nothing overlaps after the turn, and it is remembered.
        let cells = Array(layout.cells(columns: 22, rows: 15).values)
        for i in cells.indices { for j in cells.indices where j > i { #expect(!cells[i].overlaps(cells[j])) } }
        #expect(ShellLayout(encoded: layout.encoded)?.isUpright(.hand) == true)
        let laid = layout.turn(.hand, columns: 22, rows: 15)
        #expect(laid && !layout.isUpright(.hand))
        // The map and the single layers button have one shape only.
        let map = layout.turn(.map, columns: 22, rows: 15), sheets = layout.turn(.sheets, columns: 22, rows: 15)
        #expect(!map && !sheets)
        // The pencil's two rows become two columns.
        let pencilStood = layout.turn(.pencil, columns: 22, rows: 15)
        #expect(pencilStood)
        let pencil = layout.cells(columns: 22, rows: 15)[.pencil]!
        #expect(pencil.w == 2 && pencil.h == 11)
    }

    @Test func anArrangementSavedBeforeGroupsCouldStandStillLoads() {
        let old = ShellLayout.standard(leftHanded: false).encoded.replacingOccurrences(of: #","upright":null"#, with: "")
        #expect(ShellLayout(encoded: old)?.isComplete == true)
    }

    @Test func aGroupIsNotDroppedOnAnother() {
        var layout = ShellLayout.standard(leftHanded: false)
        let pencil = layout.cells(columns: columns, rows: rows)[.pencil]!
        let onPencil = layout.place(.sheets, at: .init(x: pencil.x, y: pencil.y, w: 1, h: 1), columns: columns, rows: rows)
        let offGrid = layout.place(.sheets, at: .init(x: -1, y: 3, w: 1, h: 1), columns: columns, rows: rows)
        #expect(!onPencil && !offGrid)
    }

    @Test func itIsRememberedAndABrokenRecordIsRefused() {
        var layout = ShellLayout.standard(leftHanded: true)
        layout.place(.view, at: .init(x: 5, y: 8, w: 4, h: 1), columns: columns, rows: rows)
        #expect(ShellLayout(encoded: layout.encoded) == layout)
        #expect(ShellLayout(encoded: "") == nil)
        #expect(ShellLayout(encoded: #"{"leftHanded":false,"spots":[]}"#) == nil)
    }

    @Test func controlsTakeWholeSquares() {
        #expect(UnitRow.units(Metric.cell) == 1)
        #expect(UnitRow.units(62) == 2)
    }
}

struct ShellGridTests {
    @Test func aCardOpensOnFreeSquaresNearestItsButton() {
        let grid = ShellGrid(size: CGSize(width: 834, height: 1210), insets: .init(), edgeRulers: true)
        let cells = ShellLayout.standard(leftHanded: false).cells(columns: grid.columns, rows: grid.rows)
        let taken = Array(cells.values)
        let block = grid.freeBlock(w: 8, h: 4, near: cells[.sheets]!, avoiding: taken)!
        #expect(!taken.contains(where: block.overlaps))
        #expect(block.x + block.w <= grid.columns && block.y + block.h <= grid.rows)
        // Close by: within a few squares of the button, not across the screen.
        #expect(abs(block.y + block.h - cells[.sheets]!.y) <= 4)
    }
}
