import CoreGraphics

/// Whatever shapes a stroke as it is drawn: a tool's edge, the compass, or
/// for the eraser, noticing each rub back over the same place.
enum StrokeGuide: Sendable {
    case edge(EdgeGuide)
    case arc(ArcGuide)
    case rub(RubTracker)

    /// The samples to lay down for one pencil sample.
    mutating func guide(_ sample: StrokeSample, tools: [ToolShape]) -> [StrokeSample] {
        switch self {
        case .edge(var guide):
            let out = guide.guide(sample, tools: tools)
            self = .edge(guide)
            return [out]
        case .arc(var guide):
            let out = guide.guide(sample)
            self = .arc(guide)
            return out
        case .rub(var tracker):
            let out = tracker.track(sample)
            self = .rub(tracker)
            return [out]
        }
    }

    mutating func guide(_ samples: [StrokeSample], tools: [ToolShape]) -> [StrokeSample] {
        var out: [StrokeSample] = []
        for sample in samples { out += guide(sample, tools: tools) }
        return out
    }

    var arc: ArcGuide? {
        if case .arc(let guide) = self { guide } else { nil }
    }
}
