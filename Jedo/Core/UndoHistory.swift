import Foundation

/// Undo and redo stacks that stay inside a memory budget by forgetting the
/// oldest steps first. The most recent step is always kept.
struct UndoHistory<Entry> {
    private struct Item {
        var entry: Entry
        var cost: Int
    }

    let budgetBytes: Int
    private var undoItems: [Item] = []
    private var redoItems: [Item] = []
    private(set) var totalBytes = 0

    init(budgetBytes: Int) {
        self.budgetBytes = budgetBytes
    }

    var canUndo: Bool { !undoItems.isEmpty }
    var canRedo: Bool { !redoItems.isEmpty }
    var undoCount: Int { undoItems.count }
    var redoCount: Int { redoItems.count }

    /// A new step forgets everything that could have been redone.
    mutating func record(_ entry: Entry, cost: Int) {
        totalBytes -= redoItems.reduce(0) { $0 + $1.cost }
        redoItems.removeAll()
        undoItems.append(Item(entry: entry, cost: max(cost, 0)))
        totalBytes += max(cost, 0)
        trim(toBytes: budgetBytes)
    }

    mutating func undo() -> Entry? {
        guard let item = undoItems.popLast() else { return nil }
        redoItems.append(item)
        return item.entry
    }

    mutating func redo() -> Entry? {
        guard let item = redoItems.popLast() else { return nil }
        undoItems.append(item)
        return item.entry
    }

    /// Drops the furthest redo steps, then the oldest undo steps, until under `limit`.
    mutating func trim(toBytes limit: Int) {
        while totalBytes > limit, redoItems.count > 0, undoItems.count + redoItems.count > 1 {
            totalBytes -= redoItems.removeFirst().cost
        }
        while totalBytes > limit, undoItems.count > 1 {
            totalBytes -= undoItems.removeFirst().cost
        }
    }
}
