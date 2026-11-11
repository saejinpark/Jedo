import Foundation

/// The tooth of drawing paper as a tileable height map.
///
/// Heights are rank-equalised to an even spread over 0...1, so a grain
/// threshold of 0.3 means roughly 30% of the surface sits too low for a
/// light stroke to reach. That keeps the grade table easy to reason about.
struct PaperTexture: Sendable {
    /// Side length in pixels; a power of two so wrapping is a mask.
    let size: Int
    let heights: [Float]
    private let mask: Int

    /// Paper tooth is modelled as many small rounded bumps scattered over the
    /// sheet, plus a faint lengthwise wave for the direction of the fibres.
    static let bumpsPerPixel = 1.0 / 5.0
    static let bumpRadius: ClosedRange<Float> = 0.9...2.4
    /// Lattice period in x and y (pixels) and weight of the slow undulation.
    static let octaves: [(periodX: Int, periodY: Int, weight: Float)] = [
        (16, 8, 0.10),
        (64, 32, 0.06),
        (256, 256, 0.05),
    ]

    init(size: Int = 512, seed: UInt64 = 0x5EED_CAFE) {
        precondition(size > 0 && size & (size - 1) == 0, "size must be a power of two")
        self.size = size
        self.mask = size - 1

        var rng = SplitMix64(seed: seed)
        var raw = [Float](repeating: 0, count: size * size)

        // Tooth: rounded bumps, wrapping at the edges so the texture tiles.
        let bumpCount = Int(Double(size * size) * Self.bumpsPerPixel)
        for _ in 0..<bumpCount {
            let cx = rng.nextUnitFloat() * Float(size)
            let cy = rng.nextUnitFloat() * Float(size)
            let radius = Self.bumpRadius.lowerBound
                + rng.nextUnitFloat() * (Self.bumpRadius.upperBound - Self.bumpRadius.lowerBound)
            let peak = 0.5 + rng.nextUnitFloat()
            let reach = Int((radius * 2.5).rounded(.up))
            let inv = 1 / (radius * radius)
            for oy in -reach...reach {
                let py = Int(cy) + oy
                let dy = Float(py) + 0.5 - cy
                let row = (py & (size - 1)) * size
                for ox in -reach...reach {
                    let px = Int(cx) + ox
                    let dx = Float(px) + 0.5 - cx
                    let q = (dx * dx + dy * dy) * inv
                    if q < 6.25 { raw[row + (px & (size - 1))] += peak * Self.gaussian(q) }
                }
            }
        }
        // Normalise the tooth to roughly 0...1 before adding the slow waves.
        let toothMax = max(raw.max() ?? 1, 0.0001)
        for i in raw.indices { raw[i] /= toothMax }

        for octave in Self.octaves {
            // Periods are powers of two; on a small sheet they shrink to fit so it still tiles.
            let periodX = min(octave.periodX, size), periodY = min(octave.periodY, size)
            let cellsX = size / periodX
            let cellsY = size / periodY
            var lattice = [Float](repeating: 0, count: cellsX * cellsY)
            for i in lattice.indices { lattice[i] = rng.nextUnitFloat() }
            for y in 0..<size {
                let gy = Float(y) / Float(periodY)
                let y0 = Int(gy) % cellsY
                let y1 = (y0 + 1) % cellsY
                let ty = Self.fade(gy - Float(Int(gy)))
                for x in 0..<size {
                    let gx = Float(x) / Float(periodX)
                    let x0 = Int(gx) % cellsX
                    let x1 = (x0 + 1) % cellsX
                    let tx = Self.fade(gx - Float(Int(gx)))
                    let top = lattice[y0 * cellsX + x0] * (1 - tx) + lattice[y0 * cellsX + x1] * tx
                    let bottom = lattice[y1 * cellsX + x0] * (1 - tx) + lattice[y1 * cellsX + x1] * tx
                    raw[y * size + x] += octave.weight * (top * (1 - ty) + bottom * ty)
                }
            }
        }

        // Rank-equalise to an even spread over 0...1.
        let order = raw.indices.sorted { raw[$0] < raw[$1] }
        var equalised = [Float](repeating: 0, count: raw.count)
        let last = Float(max(raw.count - 1, 1))
        for (rank, index) in order.enumerated() {
            equalised[index] = Float(rank) / last
        }
        heights = equalised
    }

    /// Paper with every point at the same height. Useful for tests.
    init(flatAt height: Float, size: Int = 64) {
        precondition(size > 0 && size & (size - 1) == 0, "size must be a power of two")
        self.size = size
        self.mask = size - 1
        heights = [Float](repeating: height, count: size * size)
    }

    /// Wraps any integer coordinate, negative ones included.
    @inline(__always)
    func height(x: Int, y: Int) -> Float {
        heights[(y & mask) * size + (x & mask)]
    }

    private static func fade(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    /// exp(-q) without calling exp in the hot loop; q is distance² / radius².
    @inline(__always)
    private static func gaussian(_ q: Float) -> Float {
        let t = max(1 - q / 6.25, 0)
        return t * t * t * t
    }
}

/// Small deterministic generator so the paper looks the same every launch.
struct SplitMix64: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnitFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

/// A cheap integer hash of a pixel and a seed, in 0..<1.
@inline(__always)
func pixelHash(_ x: Int, _ y: Int, _ seed: UInt32) -> Float {
    let h = mix32(mix32(mix32(seed) ^ UInt32(truncatingIfNeeded: x)) ^ UInt32(truncatingIfNeeded: y))
    return Float(h >> 8) / Float(1 << 24)
}

/// Chris Wellons' "lowbias32" integer finaliser.
@inline(__always)
func mix32(_ value: UInt32) -> UInt32 {
    var x = value
    x ^= x >> 16
    x &*= 0x7FEB_352D
    x ^= x >> 15
    x &*= 0x846C_A68B
    x ^= x >> 16
    return x
}
