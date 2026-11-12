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
        case eraser(EraserDynamics)
    }

    private struct ActiveStroke {
        var lead: Lead
        var spacer = DabSpacer()
        var buffer: GraphiteRaster
        var seed: UInt32
        var maxDensity: Float
        /// Tiles as they were before the stroke, kept once an earlier pass has been laid down.
        var before: [TileCoord: [Float]?] = [:]

        var erases: Bool {
            if case .eraser = lead { true } else { false }
        }
    }

    let width: Int
    let height: Int
    let pixelsPerMillimeter: Double
    let paper: PaperTexture

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
         paper: PaperTexture = PaperTexture(), historyBudgetBytes: Int = DraftingSheet.defaultHistoryBudget) {
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
    func beginStroke(grade: PencilGrade) {
        if stroke != nil { cancelStroke() }
        strokeCounter &+= 1
        stroke = ActiveStroke(
            lead: .pencil(PencilDynamics(grade: grade, pixelsPerMillimeter: pixelsPerMillimeter, style: grainStyle)),
            buffer: GraphiteRaster(width: width, height: height),
            seed: strokeCounter &* 0x9E37_79B9,
            maxDensity: Float(grade.parameters.maxDensity)
        )
    }

    /// Starts rubbing with the eraser. Samples arrive through `extendStroke`;
    /// each pass lifts a share of the graphite under it.
    func beginErasing() {
        if stroke != nil { cancelStroke() }
        strokeCounter &+= 1
        stroke = ActiveStroke(
            lead: .eraser(EraserDynamics(pixelsPerMillimeter: pixelsPerMillimeter)),
            buffer: GraphiteRaster(width: width, height: height),
            seed: strokeCounter &* 0x9E37_79B9,
            maxDensity: 1
        )
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
            stamp(sample, spacer: &active.spacer, lead: active.lead, into: &active.buffer, seed: active.seed)
        }

        clearPrediction()
        var lookahead = active.spacer
        for sample in predicted {
            stamp(sample, spacer: &lookahead, lead: active.lead, into: &prediction, seed: active.seed)
        }
        stroke = active
    }

    private func stamp(_ sample: StrokeSample, spacer: inout DabSpacer, lead: Lead,
                       into raster: inout GraphiteRaster, seed: UInt32) {
        switch lead {
        case .pencil(let dynamics):
            for dab in spacer.append(sample, spacing: { dynamics.spacing(for: dynamics.shape(for: $0)) }) {
                markDirty(DabRasterizer.stamp(center: dab.location, shape: dynamics.shape(for: dab),
                                              into: &raster, paper: paper, seed: seed))
            }
        case .eraser(let eraser):
            for dab in spacer.append(sample, spacing: { _ in eraser.spacing }) {
                markDirty(EraserRasterizer.stamp(center: dab.location, radius: eraser.radius,
                                                 strength: eraser.strength(for: dab), into: &raster, paper: paper))
            }
        }
    }

    /// Lays the stroke onto the sheet as one undoable step, every pass of it.
    func endStroke() {
        guard var active = stroke else { return }
        stroke = nil
        clearPrediction()
        layPass(&active)

        var changes: [TileCoord: TileChange] = [:]
        for (coord, before) in active.before {
            changes[coord] = TileChange(before: before, after: graphite.tile(coord))
        }
        guard !changes.isEmpty else { return }
        let edit = TileEdit(changes: changes)
        history.record(edit, cost: edit.cost)
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
            let maxDensity = active.maxDensity
            let erases = active.erases
            graphite.withMutableTile(coord) { base in
                strokeTile.withUnsafeBufferPointer { s in
                    for i in 0..<GraphiteRaster.tileArea where s[i] > 0 {
                        base[i] = erases ? GraphiteMath.erase(base: base[i], lift: s[i])
                            : GraphiteMath.composite(base: base[i], stroke: s[i], maxDensity: maxDensity)
                    }
                }
            }
            markDirty(graphite.rect(of: coord))
        }
        active.buffer.removeAll()
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
                        let v = b[y * ts + x]
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
        return active.erases ? GraphiteMath.erase(base: base, lift: s)
            : GraphiteMath.composite(base: base, stroke: s, maxDensity: active.maxDensity)
    }

    /// Writes premultiplied graphite pixels (to lay over the paper) for `rect`
    /// of a tile. `pixels` is one tile, row-major, `GraphiteRaster.tileSize` wide.
    func renderGraphite(tile coord: TileCoord, rect: PixelRect, into pixels: UnsafeMutableBufferPointer<UInt32>) {
        let size = GraphiteRaster.tileSize
        let area = rect.intersection(graphite.rect(of: coord))
        guard !area.isEmpty, pixels.count >= GraphiteRaster.tileArea else { return }
        let originX = coord.x * size, originY = coord.y * size

        let base = graphite.tile(coord)
        let strokeTile = stroke?.buffer.tile(coord)
        let predictedTile = stroke == nil ? nil : prediction.tile(coord)
        let maxDensity = stroke?.maxDensity ?? 0
        let erases = stroke?.erases ?? false
        let lut = GraphiteShading.lookup

        for py in area.minY..<area.maxY {
            let row = (py - originY) * size - originX
            for px in area.minX..<area.maxX {
                let i = row + px
                var d = base?[i] ?? 0
                let s = max(strokeTile?[i] ?? 0, predictedTile?[i] ?? 0)
                if s > 0 {
                    d = erases ? GraphiteMath.erase(base: d, lift: s) : GraphiteMath.composite(base: d, stroke: s, maxDensity: maxDensity)
                }
                pixels[i] = lut[min(Int(d * Float(GraphiteShading.levels - 1) + 0.5), GraphiteShading.levels - 1)]
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
