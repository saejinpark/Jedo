import CoreGraphics
import Testing
@testable import Jedo

struct PendingSampleQueueTests {
    func s(_ x: Double, _ p: Double = 0.5) -> StrokeSample {
        StrokeSample(location: CGPoint(x: x, y: 0), pressure: p)
    }

    @Test func finalSamplesPassStraightThrough() {
        var q = PendingSampleQueue<Int>()
        #expect(q.append(s(1), awaitingUpdate: nil).map(\.location.x) == [1])
        #expect(q.isEmpty)
    }

    @Test func estimatedSamplesWaitForTheirUpdate() {
        var q = PendingSampleQueue<Int>()
        #expect(q.append(s(1, 0.2), awaitingUpdate: 10).isEmpty)
        #expect(q.provisional.map(\.location.x) == [1])
        let released = q.update(key: 10, stillAwaiting: false) { $0.pressure = 0.7 }
        #expect(released.map(\.pressure) == [0.7])
        #expect(q.isEmpty)
    }

    @Test func laterSamplesQueueBehindAnEarlierEstimate() {
        var q = PendingSampleQueue<Int>()
        _ = q.append(s(1), awaitingUpdate: 10)
        #expect(q.append(s(2), awaitingUpdate: nil).isEmpty, "order is kept")
        _ = q.append(s(3), awaitingUpdate: 11)
        #expect(q.provisional.map(\.location.x) == [1, 2, 3])

        // An update for a later sample releases nothing while the first still waits.
        #expect(q.update(key: 11, stillAwaiting: false) { $0.pressure = 0.9 }.isEmpty)
        let released = q.update(key: 10, stillAwaiting: false) { $0.pressure = 0.1 }
        #expect(released.map(\.location.x) == [1, 2, 3])
        #expect(released.map(\.pressure) == [0.1, 0.5, 0.9])
    }

    @Test func anUpdateCanSayMoreIsComing() {
        var q = PendingSampleQueue<Int>()
        _ = q.append(s(1), awaitingUpdate: 10)
        #expect(q.update(key: 10, stillAwaiting: true) { $0.pressure = 0.3 }.isEmpty)
        #expect(q.update(key: 10, stillAwaiting: false) { $0.pressure = 0.4 }.map(\.pressure) == [0.4])
    }

    @Test func doesNotHoldBackForeverIfUpdatesNeverCome() {
        var q = PendingSampleQueue<Int>(maxHeld: 3)
        var released: [StrokeSample] = []
        for i in 0..<10 { released += q.append(s(Double(i)), awaitingUpdate: i) }
        #expect(released.map(\.location.x) == [0, 1, 2, 3, 4, 5, 6])
        #expect(q.provisional.count == 3)
    }

    @Test func flushReleasesEverythingInOrder() {
        var q = PendingSampleQueue<Int>()
        _ = q.append(s(1), awaitingUpdate: 1)
        _ = q.append(s(2), awaitingUpdate: 2)
        #expect(q.flush().map(\.location.x) == [1, 2])
        #expect(q.isEmpty)
    }

    @Test func unknownKeysAreIgnored() {
        var q = PendingSampleQueue<Int>()
        _ = q.append(s(1), awaitingUpdate: 1)
        #expect(q.update(key: 99, stillAwaiting: false) { $0.pressure = 0 }.isEmpty)
        #expect(q.provisional.first?.pressure == 0.5)
    }
}
