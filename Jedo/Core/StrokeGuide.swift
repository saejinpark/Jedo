import CoreGraphics

/// Whatever the pencil is running against for one stroke: the ruler's edge
/// or the compass. Nothing at all is `nil` at the call site.
enum StrokeGuide: Sendable {
    case edge(EdgeGuide)
    case arc(ArcGuide)

    /// The samples to draw for one pencil sample.
    mutating func guide(_ sample: StrokeSample, ruler: Ruler?) -> [StrokeSample] {
        switch self {
        case .edge(var guide):
            let out = guide.guide(sample, ruler: ruler)
            self = .edge(guide)
            return [out]
        case .arc(var guide):
            let out = guide.guide(sample)
            self = .arc(guide)
            return out
        }
    }

    mutating func guide(_ samples: [StrokeSample], ruler: Ruler?) -> [StrokeSample] {
        var out: [StrokeSample] = []
        for sample in samples { out += guide(sample, ruler: ruler) }
        return out
    }

    var arc: ArcGuide? {
        if case .arc(let guide) = self { guide } else { nil }
    }
}
