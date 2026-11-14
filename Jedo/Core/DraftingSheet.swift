import CoreGraphics
import Foundation

/// The sheet of paper and everything drawn on it: committed graphite, the
/// stroke in progress, its predicted tip, and undo history. No UIKit here,
/// so it can be tested and rendered anywhere.
final class DraftingSheet {
    struct TileChange {
        var before: [Float]?
        var after: [Float]?
    }

    /// One undoable step: the tiles a stroke changed, before and after.
    struct TileEdit {
        var changes: [TileCoord: TileChange]

        var cost: Int {
            changes.values.reduce(0) { total, change in
                total + ((change.before == nil ? 0 : 1) + (change.after == nil ? 0 : 1)) * GraphiteRaster.bytesPerTile
            }
        }
    }

    /// What the hand is moving over the paper.
    private enum Lead {
        case pencil(PencilDynamics)
        case ink(InkDynamics)
        case stylus(StylusDynamics)
        case roller(RollerDynamics)
        case eraser(EraserDynamics)
    }

    private struct ActiveStroke {
        var lead: Lead
        var spacer = DabSpacer()
        var buffer: GraphiteRaster
        var seed: UInt32
        var maxDensity: Float
        /// Where on the sheet the stroke may leave a mark.
        var mask: StrokeMask = .everywhere
        /// Tiles as they were before the stroke, kept once an earlier pass has been laid down.
        var before: [TileCoord: [Float]?] = [:]
        /// On a carbon copy: the palette colour at each pixel, from the carbon pressed through.
        var colour: (@Sendable (Int, Int) -> Int)? = nil

        var erases: Bool {
            if case .eraser = lead { true } else { false }
        }

        /// What `stroke` of this lead makes of `base` at pixel (x, y).
        @inline(__always)
        func laid(_ base: Float, _ stroke: Float, x: Int, y: Int) -> Float {
            if let colour {
                if case .eraser = lead { return CarbonPalette.erase(base: base, lift: stroke) }
                return CarbonPalette.lay(base: base, stroke: min(stroke, 1), index: colour(x, y))
            }
            return laid(base, stroke)
        }

        @inline(__always)
        func laid(_ base: Float, _ stroke: Float) -> Float {
            switch lead {
            case .pencil:
                // Graphite takes no hold on ink, and doesn't reach into a dent.
                base > 1 || base < 0 ? base : GraphiteMath.composite(base: base, stroke: stroke, maxDensity: maxDensity)
            case .ink: GraphiteMath.ink(base: base, coverage: stroke)
            case .stylus: GraphiteMath.dent(base: base, depth: stroke)
            case .roller: base
            case .eraser(let eraser): GraphiteMath.erase(base: base, lift: stroke, inkLift: eraser.kind.inkLift, dentLift: eraser.kind.dentLift)
            }
        }
    }

    let width: Int
    let height: Int
    let pixelsPerMillimeter: Double
    let paper: PaperTexture
    /// A carbon copy: its values are palette colour and density (see `CarbonPalette`).
    let isCarbonCopy: Bool
    private static let plainColourFn: @Sendable (Int, Int) -> Int = { _, _ in 0 }
    private var plainColour: @Sendable (Int, Int) -> Int { Self.plainColourFn }

    /// Applies to strokes started from now on.
    var grainStyle: GrainStyle = .standard

    private(set) var graphite: GraphiteRaster
    private var stroke: ActiveStroke?
    private var prediction: GraphiteRaster
    private var history: UndoHistory<TileEdit>
    private var strokeCounter: UInt32 = 0
    private var dirty: [TileCoord: PixelRect] = [:]

    /// 256 MB of tiles covers dozens of page-long strokes and hundreds of short ones.
    static let defaultHistoryBudget = 256 << 20

    init(width: Int, height: Int, pixelsPerMillimeter: Double,
         paper: PaperTexture = PaperTexture(), historyBudgetBytes: Int = DraftingSheet.defaultHistoryBudget,
         isCarbonCopy: Bool = false) {
        self.isCarbonCopy = isCarbonCopy
        self.width = width
        self.height = height
        self.pixelsPerMillimeter = pixelsPerMillimeter
        self.paper = paper
        graphite = GraphiteRaster(width: width, height: height)
        prediction = GraphiteRaster(width: width, height: height)
        history = UndoHistory(budgetBytes: historyBudgetBytes)
    }

    var isDrawing: Bool { stroke != nil }
    var canUndo: Bool { history.canUndo && stroke == nil }
    var canRedo: Bool { history.canRedo && stroke == nil }
    var historyBytes: Int { history.totalBytes }

    // MARK: Drawing

    /// Starts a stroke. Its first sample arrives through `extendStroke`.
    func beginStroke(grade: PencilGrade, instrument: Instrument = .wood, mask: StrokeMask = .everywhere,
                     colour: (@Sendable (Int, Int) -> Int)? = nil) {
        if stroke != nil { cancelStroke() }
        strokeCounter &+= 1
        // On anything but a carbon copy the roller rolls over and leaves nothing.
        if instrument == .roller {
            stroke = ActiveStroke(lead: .roller(RollerDynamics(pixelsPerMillimeter: pixelsPerMillimeter)),
                                  buffer: GraphiteRaster(width: width, height: height),
                                  seed: strokeCounter &* 0x9E37_79B9, maxDensity: 1, mask: mask,
                                  colour: isCarbonCopy ? (colour ?? plainColour) : nil)
            return
        }
        if isCarbonCopy {
            // Whatever presses through carbon leaves a carbon line: a point's width, in the carbon's colour.
            let point: Instrument = instrument.hasGrade ? instrument : .mechanical(.mm05)
            stroke = ActiveStroke(
                lead: .pencil(PencilDynamics(grade: .hb, pixelsPerMillimeter: pixelsPerMillimeter, instrument: point, style: grainStyle)),
                buffer: GraphiteRaster(width: width, height: height),
                seed: strokeCounter &* 0x9E37_79B9, maxDensity: 1, mask: mask, colour: colour ?? plainColour)
            return
        }
        if instrument == .stylus {
            stroke = ActiveStroke(lead: .stylus(StylusDynamics(pixelsPerMillimeter: pixelsPerMillimeter)),
                                  buffer: GraphiteRaster(width: width, height: height),
                                  seed: strokeCounter &* 0x9E37_79B9, maxDensity: 1, mask: mask)
            return
        }
        if let pen = instrument.inkPen {
            stroke = ActiveStroke(lead: .ink(InkDynamics(pen: pen, pixelsPerMillimeter: pixelsPerMillimeter)),
                                  buffer: GraphiteRaster(width: width, height: height),
                                  seed: strokeCounter &* 0x9E37_79B9, maxDensity: 1, mask: mask)
            return
        }
        stroke = ActiveStroke(
            lead: .pencil(PencilDynamics(grade: grade, pixelsPerMillimeter: pixelsPerMillimeter, instrument: instrument, style: grainStyle)),
            buffer: GraphiteRaster(width: width, height: height),
            seed: strokeCounter &* 0x9E37_79B9,
            maxDensity: Float(grade.parameters.maxDensity),
            mask: mask
        )
    }

    /// Starts rubbing with the eraser. Samples arrive through `extendStroke`;
    /// each pass lifts a share of the graphite under it.
    func beginErasing(mask: StrokeMask = .everywhere, kind: EraserKind = .rubber) {
        if stroke != nil { cancelStroke() }
        strokeCounter &+= 1
        let plain: @Sendable (Int, Int) -> Int = { _, _ in 0 }
        stroke = ActiveStroke(
            lead: .eraser(EraserDynamics(pixelsPerMillimeter: pixelsPerMillimeter, kind: kind)),
            buffer: GraphiteRaster(width: width, height: height),
            seed: strokeCounter &* 0x9E37_79B9,
            maxDensity: 1,
            mask: mask,
            colour: isCarbonCopy ? plain : nil
        )
    }

    /// Moves where the stroke in progress may mark, as when a sheet over it moves.
    func setStrokeMask(_ mask: StrokeMask) {
        stroke?.mask = mask
    }

    /// Convenience for starting a stroke with its first sample.
    func beginStroke(grade: PencilGrade, at sample: StrokeSample) {
        beginStroke(grade: grade)
        extendStroke(with: [sample], predicted: [])
    }

    /// Adds real samples, then redraws the predicted tip from `predicted`,
    /// replacing whatever was predicted last time.
    func extendStroke(with samples: [StrokeSample], predicted: [StrokeSample]) {
        guard var active = stroke else { return }
        for sample in samples {
            if sample.beginsPass { layPass(&active) }
            stamp(sample, spacer: &active.spacer, lead: active.lead, mask: active.mask, into: &active.buffer, seed: active.seed)
        }

        clearPrediction()
        var lookahead = active.spacer
        for sample in predicted {
            stamp(sample, spacer: &lookahead, lead: active.lead, mask: active.mask, into: &prediction, seed: active.seed)
        }
        stroke = active
    }

    private func stamp(_ sample: StrokeSample, spacer: inout DabSpacer, lead: Lead, mask: StrokeMask,
                       into raster: inout GraphiteRaster, seed: UInt32) {
        switch lead {
        case .pencil(let dynamics):
            for dab in spacer.append(sample, spacing: { dynamics.spacing(for: dynamics.shape(for: $0)) }) {
                let shape = dynamics.shape(for: dab)
                let coverage = mask.coverage(DabRasterizer.bounds(center: dab.location, shape: shape))
                guard coverage != .none else { continue }
                let rect = DabRasterizer.stamp(center: dab.location, shape: shape, into: &raster, paper: paper, seed: seed)
                if coverage == .part { Self.clip(&raster, rect, to: mask) }
                markDirty(rect)
            }
        case .ink(let ink):
            for dab in spacer.append(sample, spacing: { ink.spacing(for: $0) }) {
                let radius = ink.radius(for: dab)
                let coverage = mask.coverage(InkRasterizer.bounds(center: dab.location, radius: radius))
                guard coverage != .none else { continue }
                let rect = InkRasterizer.stamp(center: dab.location, radius: radius, into: &raster)
                if coverage == .part { Self.clip(&raster, rect, to: mask) }
                markDirty(rect)
            }
        case .stylus(let stylus):
            for dab in spacer.append(sample, spacing: { stylus.spacing(for: $0) }) {
                let radius = stylus.radius(for: dab)
                let coverage = mask.coverage(InkRasterizer.bounds(center: dab.location, radius: radius))
                guard coverage != .none else { continue }
                let rect = InkRasterizer.stamp(center: dab.location, radius: radius, into: &raster, strength: stylus.depth(for: dab))
                if coverage == .part { Self.clip(&raster, rect, to: mask) }
                markDirty(rect)
            }
        case .roller(let roller):
            // A cylinder: its line of contact lies across the way it rolls, and its axle turns only slowly.
            let was = spacer.heading
            spacer.steer(toward: sample, keep: 0.8)
            let dabs = spacer.append(sample, spacing: { _ in roller.spacing })
            guard let h = spacer.heading else { break }
            let from = was ?? h
            for (k, dab) in dabs.enumerated() {
                // The axle turns smoothly between samples, not in steps.
                let t = Double(k + 1) / Double(dabs.count)
                var hx = from.x + (h.x - from.x) * t, hy = from.y + (h.y - from.y) * t
                let m = max((hx * hx + hy * hy).squareRoot(), 1e-9)
                hx /= m; hy /= m
                let axis = (x: -hy, y: hx)
                let bounds = InkRasterizer.bandBounds(center: dab.location, axis: axis, half: roller.radius, thickness: roller.spacing)
                let coverage = mask.coverage(bounds)
                guard coverage != .none else { continue }
                let rect = InkRasterizer.stampBand(center: dab.location, axis: axis, half: roller.radius, thickness: roller.spacing,
                                                   into: &raster, strength: roller.strength(for: dab))
                if coverage == .part { Self.clip(&raster, rect, to: mask) }
                markDirty(rect)
            }
        case .eraser(let eraser):
            for dab in spacer.append(sample, spacing: { _ in eraser.spacing }) {
                let coverage = mask.coverage(EraserRasterizer.bounds(center: dab.location, radius: eraser.radius))
                guard coverage != .none else { continue }
                let rect = EraserRasterizer.stamp(center: dab.location, radius: eraser.radius,
                                                  strength: eraser.strength(for: dab), into: &raster, paper: paper,
                                                  valleyResistance: eraser.kind.valleyResistance)
                if coverage == .part { Self.clip(&raster, rect, to: mask) }
                markDirty(rect)
            }
        }
    }

    /// Takes back whatever a dab put outside the mask, like a line running off a sheet's edge.
    private static func clip(_ raster: inout GraphiteRaster, _ rect: PixelRect, to mask: StrokeMask) {
        guard !rect.isEmpty else { return }
        let size = GraphiteRaster.tileSize
        for coord in raster.tileCoords(overlapping: rect) where raster.tile(coord) != nil {
            let area = raster.rect(of: coord).intersection(rect)
            raster.withMutableTile(coord) { values in
                for y in area.minY..<area.maxY {
                    let row = (y - coord.y * size) * size - coord.x * size
                    for x in area.minX..<area.maxX where values[row + x] > 0 {
                        if !mask.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) { values[row + x] = 0 }
                    }
                }
            }
        }
    }

    /// Lays the stroke onto the sheet as one undoable step, every pass of it.
    /// Returns whether it changed anything (and so was recorded).
    @discardableResult
    func endStroke() -> Bool {
        guard var active = stroke else { return false }
        stroke = nil
        clearPrediction()
        layPass(&active)

        var changes: [TileCoord: TileChange] = [:]
        for (coord, before) in active.before {
            changes[coord] = TileChange(before: before, after: graphite.tile(coord))
        }
        guard !changes.isEmpty else { return false }
        let edit = TileEdit(changes: changes)
        history.record(edit, cost: edit.cost)
        return true
    }

    /// Throws the stroke away, as when the system takes the touch.
    func cancelStroke() {
        guard let active = stroke else { return }
        stroke = nil
        clearPrediction()
        for coord in active.buffer.tiles.keys { markDirty(graphite.rect(of: coord)) }
        for (coord, before) in active.before {
            graphite.setTile(coord, before)
            markDirty(graphite.rect(of: coord))
        }
    }

    /// Lays what the stroke has drawn so far onto the sheet, so the next
    /// pass darkens it. The tiles' earlier state is kept for undo.
    private func layPass(_ active: inout ActiveStroke) {
        for (coord, strokeTile) in active.buffer.tiles {
            if active.before.index(forKey: coord) == nil {
                active.before[coord] = .some(graphite.tile(coord))
            }
            let current = active
            let ts = GraphiteRaster.tileSize, ox = coord.x * ts, oy = coord.y * ts
            graphite.withMutableTile(coord) { base in
                strokeTile.withUnsafeBufferPointer { s in
                    for i in 0..<GraphiteRaster.tileArea where s[i] > 0 {
                        base[i] = current.laid(base[i], s[i], x: ox + i % ts, y: oy + i / ts)
                    }
                }
            }
            markDirty(graphite.rect(of: coord))
        }
        active.buffer.removeAll()
    }

    // MARK: Clearing

    /// Takes everything off the sheet at once, as one undoable step: a fresh
    /// sheet for the next try. Returns whether there was anything to take.
    @discardableResult
    func clear() -> Bool {
        guard stroke == nil, !graphite.isEmpty else { return false }
        var changes: [TileCoord: TileChange] = [:]
        for (coord, tile) in graphite.tiles {
            changes[coord] = TileChange(before: tile, after: nil)
            markDirty(graphite.rect(of: coord))
        }
        graphite.removeAll()
        let edit = TileEdit(changes: changes)
        history.record(edit, cost: edit.cost)
        return true
    }

    // MARK: Picking up again

    /// Lays back graphite saved earlier, with nothing to undo before it.
    func load(_ saved: GraphiteRaster) {
        guard stroke == nil, saved.width == width, saved.height == height else { return }
        for coord in graphite.tiles.keys { markDirty(graphite.rect(of: coord)) }
        graphite = saved
        for coord in graphite.tiles.keys { markDirty(graphite.rect(of: coord)) }
    }

    // MARK: Stamping

    /// Presses another surface's graphite onto this sheet, as one undoable step:
    /// a grid sheet's drawing printed onto the paper under it. `sourcePoint`
    /// takes a point of this sheet to the same place on the source. The
    /// source is left as it was. Returns whether anything was laid.
    @discardableResult
    func imprint(_ source: GraphiteRaster, over area: PixelRect, mask: StrokeMask = .everywhere,
                 colour: ((Int, Int) -> Int)? = nil, sourcePoint: (CGPoint) -> CGPoint) -> Bool {
        guard stroke == nil, !source.isEmpty else { return false }
        let ts = GraphiteRaster.tileSize
        var changes: [TileCoord: TileChange] = [:]
        for coord in graphite.tileCoords(overlapping: area) {
            let rect = graphite.rect(of: coord).intersection(area)
            let coverage = mask.coverage(rect)
            guard coverage != .none else { continue }
            // Skip tiles whose footprint on the source has no graphite.
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].map(sourcePoint)
            let reach = PixelRect(minX: Int(corners.map { Double($0.x) }.min()!.rounded(.down)) - 1,
                                  minY: Int(corners.map { Double($0.y) }.min()!.rounded(.down)) - 1,
                                  maxX: Int(corners.map { Double($0.x) }.max()!.rounded(.up)) + 2,
                                  maxY: Int(corners.map { Double($0.y) }.max()!.rounded(.up)) + 2)
            guard source.tileCoords(overlapping: reach).contains(where: { source.tile($0) != nil }) else { continue }

            let before = graphite.tile(coord)
            var laid = false
            graphite.withMutableTile(coord) { base in
                for y in rect.minY..<rect.maxY {
                    for x in rect.minX..<rect.maxX {
                        let p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                        if coverage == .part, !mask.contains(p) { continue }
                        let v = Self.sample(source, at: sourcePoint(p))
                        guard v > 0.002 else { continue }
                        let i = (y - coord.y * ts) * ts + (x - coord.x * ts)
                        if isCarbonCopy {
                            base[i] = CarbonPalette.lay(base: base[i], stroke: min(v, 1), index: colour?(x, y) ?? 0)
                            laid = true
                            continue
                        }
                        // A dent keeps out what is pressed onto it, as it keeps out graphite.
                        if base[i] < 0, v <= 1 { continue }
                        base[i] = v > 1 ? GraphiteMath.ink(base: base[i], coverage: GraphiteMath.inkCoverage(v))
                            : GraphiteMath.composite(base: base[i], stroke: v, maxDensity: 1)
                        laid = true
                    }
                }
            }
            if laid {
                changes[coord] = TileChange(before: before, after: graphite.tile(coord))
                markDirty(graphite.rect(of: coord))
            } else {
                graphite.setTile(coord, before)
            }
        }
        guard !changes.isEmpty else { return false }
        let edit = TileEdit(changes: changes)
        history.record(edit, cost: edit.cost)
        return true
    }

    /// Graphite at a point between pixel centres, blended from the four around it.
    private static func sample(_ raster: GraphiteRaster, at p: CGPoint) -> Float {
        let fx = Double(p.x) - 0.5, fy = Double(p.y) - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let tx = Float(fx - Double(x0)), ty = Float(fy - Double(y0))
        let a = raster.value(x: x0, y: y0), b = raster.value(x: x0 + 1, y: y0)
        let c = raster.value(x: x0, y: y0 + 1), d = raster.value(x: x0 + 1, y: y0 + 1)
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
    }

    // MARK: Undo

    @discardableResult
    func undo() -> Bool {
        guard stroke == nil, let edit = history.undo() else { return false }
        apply(edit, useAfter: false)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard stroke == nil, let edit = history.redo() else { return false }
        apply(edit, useAfter: true)
        return true
    }

    func trimHistory(toBytes limit: Int) {
        history.trim(toBytes: limit)
    }

    private func apply(_ edit: TileEdit, useAfter: Bool) {
        for (coord, change) in edit.changes {
            graphite.setTile(coord, useAfter ? change.after : change.before)
            markDirty(graphite.rect(of: coord))
        }
    }

    // MARK: Display

    /// A small picture of the graphite on the sheet: the darkest density in
    /// each cell of a `size` by `size` grid, row by row from the top.
    func overview(size: Int) -> [Float] {
        var out = [Float](repeating: 0, count: size * size)
        guard size > 0 else { return out }
        let cellWidth = Double(width) / Double(size), cellHeight = Double(height) / Double(size)
        let ts = GraphiteRaster.tileSize
        for (coord, tile) in graphite.tiles {
            let ox = coord.x * ts, oy = coord.y * ts
            tile.withUnsafeBufferPointer { b in
                // Every other pixel is enough: the finest line is three pixels wide.
                for y in stride(from: 0, to: ts, by: 2) where oy + y < height {
                    let row = min(Int(Double(oy + y) / cellHeight), size - 1) * size
                    for x in stride(from: 0, to: ts, by: 2) where ox + x < width {
                        let v = min(b[y * ts + x], 1)
                        guard v > 0 else { continue }
                        let i = row + min(Int(Double(ox + x) / cellWidth), size - 1)
                        if v > out[i] { out[i] = v }
                    }
                }
            }
        }
        return out
    }

    /// The regions that need redrawing since last asked, one rect per tile.
    func takeDirtyRegions() -> [TileCoord: PixelRect] {
        defer { dirty.removeAll(keepingCapacity: true) }
        return dirty
    }

    /// Graphite density as it should look right now, stroke in progress included.
    func displayedDensity(x: Int, y: Int) -> Float {
        let base = graphite.value(x: x, y: y)
        guard let active = stroke else { return base }
        let s = max(active.buffer.value(x: x, y: y), prediction.value(x: x, y: y))
        return s > 0 ? active.laid(base, s, x: x, y: y) : base
    }

    /// Writes premultiplied graphite pixels (to lay over the paper) for `rect`
    /// of a tile. `pixels` is one tile, row-major, `GraphiteRaster.tileSize` wide.
    /// Ink shows as ink with `inkShading`, or, with nil, as the fullest step of `lut`
    /// (a carbon copy of an inked line is carbon all the same).
    func renderGraphite(tile coord: TileCoord, rect: PixelRect, into pixels: UnsafeMutableBufferPointer<UInt32>,
                        shading lut: [UInt32] = GraphiteShading.lookup, inkShading: [UInt32]? = GraphiteShading.inkLookup) {
        let size = GraphiteRaster.tileSize
        let area = rect.intersection(graphite.rect(of: coord))
        guard !area.isEmpty, pixels.count >= GraphiteRaster.tileArea else { return }
        let originX = coord.x * size, originY = coord.y * size

        let base = graphite.tile(coord)
        let strokeTile = stroke?.buffer.tile(coord)
        let predictedTile = stroke == nil ? nil : prediction.tile(coord)
        let active = stroke
        let top = GraphiteShading.levels - 1

        for py in area.minY..<area.maxY {
            let row = (py - originY) * size - originX
            for px in area.minX..<area.maxX {
                let i = row + px
                var d = base?[i] ?? 0
                let s = max(strokeTile?[i] ?? 0, predictedTile?[i] ?? 0)
                if s > 0, let active { d = active.laid(d, s, x: px, y: py) }
                if isCarbonCopy {
                    let (index, density) = CarbonPalette.split(d)
                    let c = CarbonPalette.colours[index], a = Double(density)
                    pixels[i] = GraphiteShading.pack(r: c.r * a, g: c.g * a, b: c.b * a, a: a)
                } else if d < 0 {
                    pixels[i] = GraphiteShading.dentLookup[min(Int(-d * Float(top) + 0.5), top)]
                } else if d > 1, let inkShading {
                    pixels[i] = inkShading[min(Int((d - 1) * Float(top) + 0.5), top)]
                } else {
                    pixels[i] = lut[min(Int(min(d, 1) * Float(top) + 0.5), top)]
                }
            }
        }
    }

    // MARK: Private

    private func clearPrediction() {
        guard !prediction.isEmpty else { return }
        for coord in prediction.tiles.keys { markDirty(prediction.rect(of: coord)) }
        prediction.removeAll()
    }

    private func markDirty(_ rect: PixelRect) {
        let clipped = rect.intersection(graphite.bounds)
        guard !clipped.isEmpty else { return }
        for coord in graphite.tileCoords(overlapping: clipped) {
            let part = graphite.rect(of: coord).intersection(clipped)
            dirty[coord] = (dirty[coord] ?? .empty).union(part)
        }
    }
}
