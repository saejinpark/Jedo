import Foundation

struct TileCoord: Hashable, Sendable {
    var x: Int
    var y: Int
}

/// A half-open rectangle of pixels: `minX..<maxX`, `minY..<maxY`.
struct PixelRect: Equatable, Sendable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    static let empty = PixelRect(minX: 0, minY: 0, maxX: 0, maxY: 0)

    var width: Int { max(maxX - minX, 0) }
    var height: Int { max(maxY - minY, 0) }
    var isEmpty: Bool { maxX <= minX || maxY <= minY }

    func intersection(_ other: PixelRect) -> PixelRect {
        let r = PixelRect(minX: max(minX, other.minX), minY: max(minY, other.minY),
                          maxX: min(maxX, other.maxX), maxY: min(maxY, other.maxY))
        return r.isEmpty ? .empty : r
    }

    func union(_ other: PixelRect) -> PixelRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return PixelRect(minX: min(minX, other.minX), minY: min(minY, other.minY),
                         maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
    }
}

/// A sparse grid of float tiles. Tiles that were never touched are absent and read as 0.
///
/// Tiles are plain arrays, so keeping a copy of one (for undo) costs nothing
/// until the raster writes to it again.
struct GraphiteRaster: Sendable {
    static let tileSize = 128
    static let tileArea = tileSize * tileSize
    static let bytesPerTile = tileArea * MemoryLayout<Float>.stride

    let width: Int
    let height: Int
    private(set) var tiles: [TileCoord: [Float]] = [:]

    init(width: Int, height: Int) {
        self.width = max(width, 0)
        self.height = max(height, 0)
    }

    var bounds: PixelRect { PixelRect(minX: 0, minY: 0, maxX: width, maxY: height) }
    var isEmpty: Bool { tiles.isEmpty }

    func value(x: Int, y: Int) -> Float {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        let coord = TileCoord(x: x / Self.tileSize, y: y / Self.tileSize)
        guard let tile = tiles[coord] else { return 0 }
        return tile[(y % Self.tileSize) * Self.tileSize + x % Self.tileSize]
    }

    func tile(_ coord: TileCoord) -> [Float]? { tiles[coord] }

    mutating func setTile(_ coord: TileCoord, _ values: [Float]?) {
        precondition(values == nil || values!.count == Self.tileArea)
        tiles[coord] = values
    }

    mutating func removeAll() { tiles.removeAll(keepingCapacity: true) }

    /// Gives mutable access to a tile, creating it zero-filled if needed.
    /// The tile is taken out of the dictionary first so writing to it never copies.
    mutating func withMutableTile<R>(_ coord: TileCoord, _ body: (UnsafeMutableBufferPointer<Float>) -> R) -> R {
        var values = tiles.removeValue(forKey: coord) ?? [Float](repeating: 0, count: Self.tileArea)
        let result = values.withUnsafeMutableBufferPointer { body($0) }
        tiles[coord] = values
        return result
    }

    /// The pixels a tile covers, clipped to the raster.
    func rect(of coord: TileCoord) -> PixelRect {
        PixelRect(minX: coord.x * Self.tileSize, minY: coord.y * Self.tileSize,
                  maxX: coord.x * Self.tileSize + Self.tileSize,
                  maxY: coord.y * Self.tileSize + Self.tileSize).intersection(bounds)
    }

    func tileCoords(overlapping rect: PixelRect) -> [TileCoord] {
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty else { return [] }
        var coords: [TileCoord] = []
        for ty in (clipped.minY / Self.tileSize)...((clipped.maxY - 1) / Self.tileSize) {
            for tx in (clipped.minX / Self.tileSize)...((clipped.maxX - 1) / Self.tileSize) {
                coords.append(TileCoord(x: tx, y: ty))
            }
        }
        return coords
    }
}
