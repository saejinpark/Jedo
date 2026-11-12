import CoreGraphics
import Foundation

/// What one stroke did, for judging hand-feel from the iPad without
/// watching over the user's shoulder: where the pencil really went and
/// where the line was drawn, so the pull of a tool's edge can be measured.
struct StrokeRecord: Codable, Equatable, Sendable {
    /// What guided the line: "edge", "arc" or "rub".
    var guide: String
    var grade: String
    /// Tools lying on the paper.
    var tools: [String]
    var startedAt: Date
    var seconds: Double
    /// Pencil and line, in millimetres on the paper, every sample.
    var pencil: [[Double]]
    var line: [[Double]]
    var pressure: [Double]
    /// How blunt the point was, every sample (0 sharp ... 1 flat). Missing in older logs.
    var bluntness: [Double]? = nil

    /// How far the line was moved off the pencil, in millimetres.
    var pull: (max: Double, mean: Double, movedShare: Double) {
        let d = zip(pencil, line).map { hypot($0[0] - $1[0], $0[1] - $1[1]) }
        guard !d.isEmpty else { return (0, 0, 0) }
        let moved = d.filter { $0 > 0.2 }.count
        return (d.max() ?? 0, d.reduce(0, +) / Double(d.count), Double(moved) / Double(d.count))
    }

    /// Length of the pencil's path, in millimetres.
    var length: Double {
        zip(pencil, pencil.dropFirst()).reduce(0) { $0 + hypot($1.1[0] - $1.0[0], $1.1[1] - $1.0[1]) }
    }
}

/// Collects one stroke's samples as they are guided.
struct StrokeRecorder: Sendable {
    let pixelsPerMillimeter: Double
    private(set) var pencil: [[Double]] = []
    private(set) var line: [[Double]] = []
    private(set) var pressure: [Double] = []
    private(set) var bluntness: [Double] = []

    init(pixelsPerMillimeter: Double) {
        self.pixelsPerMillimeter = pixelsPerMillimeter
    }

    mutating func add(pencil raw: [StrokeSample], line drawn: [StrokeSample]) {
        for (r, d) in zip(raw, drawn) {
            pencil.append([Double(r.location.x) / pixelsPerMillimeter, Double(r.location.y) / pixelsPerMillimeter])
            line.append([Double(d.location.x) / pixelsPerMillimeter, Double(d.location.y) / pixelsPerMillimeter])
            pressure.append(r.pressure)
            bluntness.append(d.bluntness)
        }
    }

    func record(guide: String, grade: String, tools: [String], startedAt: Date, seconds: Double) -> StrokeRecord {
        // Two decimals is a hundredth of a millimetre: plenty.
        let round = { (v: [[Double]]) in v.map { $0.map { ($0 * 100).rounded() / 100 } } }
        return StrokeRecord(guide: guide, grade: grade, tools: tools, startedAt: startedAt, seconds: seconds,
                            pencil: round(pencil), line: round(line), pressure: pressure.map { ($0 * 100).rounded() / 100 },
                            bluntness: bluntness.map { ($0 * 100).rounded() / 100 })
    }
}
