import CoreGraphics

/// Walks along the pencil's path and drops dabs at even spacing, carrying the
/// leftover distance between batches of touches.
///
/// It is a value type on purpose: a copy can be fed predicted touches without
/// disturbing the real stroke.
struct DabSpacer: Sendable {
    private(set) var last: StrokeSample?
    /// Distance still to travel before the next dab.
    private(set) var distanceToNextDab: Double = 0

    /// Adds a sample and returns the dabs it produces.
    /// `spacing` gives the gap to leave after a dab.
    mutating func append(_ sample: StrokeSample, spacing: (StrokeSample) -> Double) -> [StrokeSample] {
        guard let previous = last else {
            last = sample
            distanceToNextDab = Self.safe(spacing(sample))
            return [sample]
        }
        last = sample

        let dx = sample.location.x - previous.location.x
        let dy = sample.location.y - previous.location.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return [] }

        var dabs: [StrokeSample] = []
        var travelled = 0.0
        while distanceToNextDab <= length - travelled {
            travelled += distanceToNextDab
            let dab = StrokeSample.interpolate(previous, sample, travelled / length)
            dabs.append(dab)
            distanceToNextDab = Self.safe(spacing(dab))
        }
        distanceToNextDab -= length - travelled
        return dabs
    }

    private static func safe(_ spacing: Double) -> Double {
        spacing.isFinite ? max(spacing, 0.1) : 1
    }
}
