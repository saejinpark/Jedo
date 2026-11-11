import Testing
@testable import Jedo

struct UndoHistoryTests {
    @Test func undoAndRedoWalkTheSteps() {
        var h = UndoHistory<String>(budgetBytes: 100)
        h.record("a", cost: 1)
        h.record("b", cost: 1)
        #expect(h.undo() == "b")
        #expect(h.undo() == "a")
        #expect(h.undo() == nil)
        #expect(h.redo() == "a")
        #expect(h.redo() == "b")
        #expect(h.redo() == nil)
    }

    @Test func aNewStepForgetsTheRedoBranch() {
        var h = UndoHistory<String>(budgetBytes: 100)
        h.record("a", cost: 10)
        h.record("b", cost: 10)
        _ = h.undo()
        h.record("c", cost: 10)
        #expect(!h.canRedo)
        #expect(h.totalBytes == 20)
        #expect(h.undo() == "c")
        #expect(h.undo() == "a")
    }

    @Test func forgetsTheOldestStepsToStayInBudget() {
        var h = UndoHistory<Int>(budgetBytes: 30)
        for i in 1...5 { h.record(i, cost: 10) }
        #expect(h.undoCount == 3)
        #expect(h.totalBytes == 30)
        #expect(h.undo() == 5)
        #expect(h.undo() == 4)
        #expect(h.undo() == 3)
        #expect(h.undo() == nil)
    }

    @Test func alwaysKeepsTheLatestStepEvenIfHuge() {
        var h = UndoHistory<Int>(budgetBytes: 10)
        h.record(1, cost: 5)
        h.record(2, cost: 500)
        #expect(h.undoCount == 1)
        #expect(h.undo() == 2)
    }

    @Test func trimmingDropsFarRedoBeforeUndo() {
        var h = UndoHistory<Int>(budgetBytes: 1000)
        for i in 1...4 { h.record(i, cost: 10) }
        _ = h.undo() // 4 to redo
        _ = h.undo() // 3 to redo
        h.trim(toBytes: 30)
        #expect(h.redoCount == 1)
        #expect(h.redo() == 3)
        h.trim(toBytes: 10)
        #expect(h.undoCount == 1)
        #expect(h.undo() == 3)
    }
}
