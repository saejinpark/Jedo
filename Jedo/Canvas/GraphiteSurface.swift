import UIKit

/// A drawing surface on screen: the paper itself, what the carbon copied
/// onto it, or a grid sheet's own surface. Graphite sits in 128-pixel tiles
/// that are created when first drawn on and redrawn only where they changed.
@MainActor
final class GraphiteSurface {
    let sheet: DraftingSheet
    /// Holds the tiles, in the surface's own points from its top-left corner.
    let layer = CALayer()
    private let scale: CGFloat
    private let shading: [UInt32]
    private let inkShading: [UInt32]?
    private var tiles: [TileCoord: GraphiteTile] = [:]

    /// Carbon copies (`shading` of carbon) show inked lines as carbon too.
    init(sheet: DraftingSheet, scale: CGFloat, shading: [UInt32] = GraphiteShading.lookup) {
        self.sheet = sheet
        self.scale = scale
        self.shading = shading
        inkShading = shading == GraphiteShading.carbonLookup ? nil : GraphiteShading.inkLookup
        layer.actions = CanvasView.noAnimations
        layer.frame = CGRect(x: 0, y: 0, width: CGFloat(sheet.width) / scale, height: CGFloat(sheet.height) / scale)
    }

    /// Redraws whatever changed since last time.
    func refresh() {
        let regions = sheet.takeDirtyRegions()
        guard !regions.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (coord, rect) in regions {
            let tile = tiles[coord] ?? makeTile(coord)
            tile.pixels.withUnsafeMutableBufferPointer {
                sheet.renderGraphite(tile: coord, rect: rect, into: $0, shading: shading, inkShading: inkShading)
            }
            tile.layer.contents = CanvasView.makeImage(pixels: tile.pixels, width: GraphiteRaster.tileSize,
                                                       height: GraphiteRaster.tileSize)
        }
        CATransaction.commit()
    }

    private func makeTile(_ coord: TileCoord) -> GraphiteTile {
        let side = CGFloat(GraphiteRaster.tileSize) / scale
        let tileLayer = CALayer()
        tileLayer.frame = CGRect(x: CGFloat(coord.x) * side, y: CGFloat(coord.y) * side, width: side, height: side)
        tileLayer.contentsScale = scale
        tileLayer.magnificationFilter = .nearest
        tileLayer.actions = CanvasView.noAnimations
        layer.addSublayer(tileLayer)
        let tile = GraphiteTile(layer: tileLayer)
        tiles[coord] = tile
        return tile
    }
}

/// One tile of graphite on screen and the pixels behind it.
private final class GraphiteTile {
    let layer: CALayer
    var pixels = [UInt32](repeating: 0, count: GraphiteRaster.tileArea)
    init(layer: CALayer) { self.layer = layer }
}
