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

    private struct ActiveStroke {
        var dynamics: PencilDynamics
        var spacer = DabSpacer()
        var buffer: GraphiteRaster
        var seed: UInt32
        var maxDensity: Float
    }

    let width: Int
    let height: Int
    let pixelsPerMillimeter: Double
    let paper: PaperTexture

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
            dynamics: PencilDynamics(grade: grade, pixelsPerMillimeter: pixelsPerMillimeter),
            buffer: GraphiteRaster(width: width, height: height),
            seed: strokeCounter &* 0x9E37_79B9,
            maxDensity: Float(grade.parameters.maxDensity)
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
        let dynamics = active.dynamics
        for sample in samples {
            for dab in active.spacer.append(sample, spacing: { dynamics.spacing(for: dynamics.shape(for: $0)) }) {
                let rect = DabRasterizer.stamp(center: dab.location, shape: dynamics.shape(for: dab),
                                               into: &active.buffer, paper: paper, seed: active.seed)
                markDirty(rect)
            }
        }

        clearPrediction()
        var lookahead = active.spacer
        for sample in predicted {
            for dab in lookahead.append(sample, spacing: { dynamics.spacing(for: dynamics.shape(for: $0)) }) {
                let rect = DabRasterizer.stamp(center: dab.location, shape: dynamics.shape(for: dab),
                                               into: &prediction, paper: paper, seed: active.seed)
                markDirty(rect)
            }
        }
        stroke = active
    }

    /// Lays the stroke onto the sheet as one undoable step.
    func endStroke() {
        guard let active = stroke else { return }
        stroke = nil
        clearPrediction()

        var changes: [TileCoord: TileChange] = [:]
        for (coord, strokeTile) in active.buffer.tiles {
            let before = graphite.tile(coord)
            graphite.withMutableTile(coord) { base in
                strokeTile.withUnsafeBufferPointer { s in
                    for i in 0..<GraphiteRaster.tileArea where s[i] > 0 {
                        base[i] = GraphiteMath.composite(base: base[i], stroke: s[i], maxDensity: active.maxDensity)
                    }
                }
            }
            changes[coord] = TileChange(before: before, after: graphite.tile(coord))
            markDirty(graphite.rect(of: coord))
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
        return GraphiteMath.composite(base: base, stroke: s, maxDensity: active.maxDensity)
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
        let lut = GraphiteShading.lookup

        for py in area.minY..<area.maxY {
            let row = (py - originY) * size - originX
            for px in area.minX..<area.maxX {
                let i = row + px
                var d = base?[i] ?? 0
                let s = max(strokeTile?[i] ?? 0, predictedTile?[i] ?? 0)
                if s > 0 { d = GraphiteMath.composite(base: d, stroke: s, maxDensity: maxDensity) }
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
