import Foundation

/// Holds pencil samples whose force is still an estimate until Apple Pencil
/// sends the measured value, and releases samples strictly in order.
///
/// While waiting, the samples are drawn like predicted touches, so the line
/// on screen keeps up with the pencil; they join the stroke for real only
/// once their pressure is known.
struct PendingSampleQueue<Key: Hashable> {
    private struct Item {
        var key: Key?
        var sample: StrokeSample
        var awaiting: Bool
    }

    /// Never hold more than this many samples back, in case an update never comes.
    /// Pencil samples arrive at 240 Hz, so 24 is a tenth of a second.
    let maxHeld: Int
    private var items: [Item] = []

    init(maxHeld: Int = 24) {
        self.maxHeld = max(maxHeld, 1)
    }

    var isEmpty: Bool { items.isEmpty }

    /// Samples still waiting (and any queued behind them), oldest first.
    var provisional: [StrokeSample] { items.map(\.sample) }

    /// Adds a sample. Pass the update key if its force will be refined later.
    /// Returns the samples that are now final, oldest first.
    mutating func append(_ sample: StrokeSample, awaitingUpdate key: Key?) -> [StrokeSample] {
        items.append(Item(key: key, sample: sample, awaiting: key != nil))
        return drain()
    }

    /// Applies a refined reading to the sample with `key`.
    mutating func update(key: Key, stillAwaiting: Bool, _ change: (inout StrokeSample) -> Void) -> [StrokeSample] {
        if let index = items.firstIndex(where: { $0.key == key }) {
            change(&items[index].sample)
            items[index].awaiting = stillAwaiting
        }
        return drain()
    }

    /// Releases everything, as when the pencil lifts.
    mutating func flush() -> [StrokeSample] {
        defer { items.removeAll() }
        return items.map(\.sample)
    }

    private mutating func drain() -> [StrokeSample] {
        var released: [StrokeSample] = []
        while let first = items.first, !first.awaiting || items.count > maxHeld {
            released.append(first.sample)
            items.removeFirst()
        }
        return released
    }
}
