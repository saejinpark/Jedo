import CoreGraphics

/// Tells a finger held still on the paper from a tap or a finger that moves.
/// Times are seconds on any steady clock; points are canvas pixels.
struct LongPress<Key: Hashable> {
    enum Ending: Equatable { case tap, other }

    private struct Press {
        var start: CGPoint
        var time: Double
        var moved = false
    }

    /// How long a finger must stay put.
    let duration: Double
    /// How far it may drift and still count as still.
    let slop: Double
    /// A touch lifted sooner than this, without moving, is a tap.
    let tapDuration: Double
    private var presses: [Key: Press] = [:]

    init(duration: Double = 0.4, slop: Double, tapDuration: Double = 0.3) {
        self.duration = duration
        self.slop = slop
        self.tapDuration = tapDuration
    }

    var isEmpty: Bool { presses.isEmpty }

    mutating func begin(_ key: Key, at point: CGPoint, time: Double) {
        presses[key] = Press(start: point, time: time)
    }

    /// Returns true the moment a press drifts too far to count.
    mutating func move(_ key: Key, to point: CGPoint) -> Bool {
        guard var press = presses[key], !press.moved else { return false }
        let drift = hypot(Double(point.x - press.start.x), Double(point.y - press.start.y))
        guard drift > slop else { return false }
        press.moved = true
        presses[key] = press
        return true
    }

    /// Forgets the press; says whether it was a tap.
    mutating func end(_ key: Key, time: Double) -> Ending? {
        guard let press = presses.removeValue(forKey: key) else { return nil }
        return !press.moved && time - press.time < tapDuration ? .tap : .other
    }

    /// Where a press still being followed began.
    func start(of key: Key) -> CGPoint? { presses[key]?.start }

    /// Presses that have not moved yet, with where they started: fingers
    /// that might still turn out to be part of a two-finger hold.
    func still() -> [(key: Key, point: CGPoint)] {
        presses.filter { !$0.value.moved }.sorted { $0.value.time < $1.value.time }.map { ($0.key, $0.value.start) }
    }

    mutating func cancel(_ key: Key) {
        presses.removeValue(forKey: key)
    }

    /// Presses held still long enough by `time`, with where they started.
    /// Each is reported once and then forgotten.
    mutating func due(at time: Double) -> [(key: Key, point: CGPoint)] {
        let ready = presses.filter { !$0.value.moved && time - $0.value.time >= duration }
        for key in ready.keys { presses.removeValue(forKey: key) }
        return ready.sorted { $0.value.time < $1.value.time }.map { ($0.key, $0.value.start) }
    }
}
