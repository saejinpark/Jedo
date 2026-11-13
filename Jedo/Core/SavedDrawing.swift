import CoreGraphics
import Foundation

/// Everything on the desk that is the drawing, as it is at one moment: the
/// paper and what is drawn on it, and every sheet lying on it with its own
/// drawing. Tools are not part of it; they go back in the drawer, as at the
/// end of a day. Neither is undo: a drawing picked up again starts fresh.
struct DrawingState: Sendable {
    struct Sheet: Sendable {
        var layer: PaperLayer
        var hidden: Bool
        var graphite: GraphiteRaster?
        var copies: GraphiteRaster?
        var tone: ToneCut?
    }

    var paper: PaperSize
    var pixelsPerMillimeter: Double
    /// Side of the square desk, in pixels.
    var deskSide: Int
    var paperGraphite: GraphiteRaster
    var carbonCopy: GraphiteRaster
    /// Bottom first.
    var sheets: [Sheet]
    var nextLayerID: Int
    var pins: [CGPoint]
}

/// Keeps the drawing in a file of its own, so it is still there when the
/// app comes back. Written whole each time, compressed, in one atomic write.
enum DrawingStore {
    static let format = 1

    static var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("drawing.jedo")
    }

    static func encode(_ state: DrawingState) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let raw = try encoder.encode(Saved(state))
        return try (raw as NSData).compressed(using: .lzfse) as Data
    }

    static func decode(_ data: Data) throws -> DrawingState {
        let raw = try (data as NSData).decompressed(using: .lzfse) as Data
        return try PropertyListDecoder().decode(Saved.self, from: raw).state()
    }

    static func save(_ state: DrawingState, to url: URL = url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load(from url: URL = url) -> DrawingState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    static func remove(at url: URL = url) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: On disk

    struct Unreadable: Error {}

    private struct Saved: Codable {
        var format: Int
        var series: String
        var landscape: Bool
        var screenMM: [Double]
        var pixelsPerMillimeter: Double
        var deskSide: Int
        var paperGraphite: Raster
        var carbonCopy: Raster
        var sheets: [Sheet]
        var nextLayerID: Int
        var pins: [Double]

        struct Sheet: Codable {
            var id: Int
            var kind: String
            var pose: [Double]
            var hidden: Bool
            var graphite: Raster?
            var copies: Raster?
            var tone: Tone?
        }

        init(_ s: DrawingState) {
            format = DrawingStore.format
            series = "\(s.paper.series)"
            landscape = s.paper.landscape
            screenMM = [s.paper.screenWidthMM, s.paper.screenHeightMM]
            pixelsPerMillimeter = s.pixelsPerMillimeter
            deskSide = s.deskSide
            paperGraphite = Raster(s.paperGraphite)
            carbonCopy = Raster(s.carbonCopy)
            sheets = s.sheets.map { sheet in
                let pose = sheet.layer.pose
                return Sheet(id: sheet.layer.id, kind: sheet.layer.kind.code,
                             pose: [Double(pose.center.x), Double(pose.center.y), pose.angle], hidden: sheet.hidden,
                             graphite: sheet.graphite.map(Raster.init), copies: sheet.copies.map(Raster.init),
                             tone: sheet.tone.map(Tone.init))
            }
            nextLayerID = s.nextLayerID
            pins = s.pins.flatMap { [Double($0.x), Double($0.y)] }
        }

        func state() throws -> DrawingState {
            guard format == DrawingStore.format,
                  let series = PaperSize.Series.allCases.first(where: { "\($0)" == self.series }),
                  screenMM.count == 2, pins.count.isMultiple(of: 2) else { throw Unreadable() }
            let paper = PaperSize(series: series, landscape: landscape, screenWidthMM: screenMM[0], screenHeightMM: screenMM[1])
            let size = deskSide
            return try DrawingState(
                paper: paper, pixelsPerMillimeter: pixelsPerMillimeter, deskSide: deskSide,
                paperGraphite: paperGraphite.raster(width: size, height: size),
                carbonCopy: carbonCopy.raster(width: size, height: size),
                sheets: sheets.map { sheet in
                    guard let kind = SheetKind(code: sheet.kind), sheet.pose.count == 3 else { throw Unreadable() }
                    let layer = PaperLayer(id: sheet.id, kind: kind,
                                           pose: ToolPose(center: CGPoint(x: sheet.pose[0], y: sheet.pose[1]), angle: sheet.pose[2]))
                    let r = layer.rasterSize(pixelsPerMillimeter: pixelsPerMillimeter)
                    return DrawingState.Sheet(layer: layer, hidden: sheet.hidden,
                                              graphite: try sheet.graphite?.raster(width: r.width, height: r.height),
                                              copies: try sheet.copies?.raster(width: r.width, height: r.height),
                                              tone: try sheet.tone?.cut())
                },
                nextLayerID: nextLayerID,
                pins: stride(from: 0, to: pins.count, by: 2).map { CGPoint(x: pins[$0], y: pins[$0 + 1]) })
        }
    }

    /// Only the tiles that were drawn on, each as its raw floats.
    private struct Raster: Codable {
        var tiles: [Int]
        var values: [Data]

        init(_ raster: GraphiteRaster) {
            let coords = raster.tiles.keys.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            tiles = coords.flatMap { [$0.x, $0.y] }
            values = coords.map { raster.tiles[$0]!.withUnsafeBytes { Data($0) } }
        }

        func raster(width: Int, height: Int) throws -> GraphiteRaster {
            guard tiles.count == values.count * 2 else { throw Unreadable() }
            var raster = GraphiteRaster(width: width, height: height)
            for (n, data) in values.enumerated() {
                guard data.count == GraphiteRaster.bytesPerTile else { throw Unreadable() }
                var floats = [Float](repeating: 0, count: GraphiteRaster.tileArea)
                _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }
                raster.setTile(TileCoord(x: tiles[2 * n], y: tiles[2 * n + 1]), floats)
            }
            return raster
        }
    }

    private struct Tone: Codable {
        var columns: Int
        var rows: Int
        var cells: Data
        var ink: Data

        init(_ cut: ToneCut) {
            columns = cut.columns
            rows = cut.rows
            cells = Data(cut.cells.map(\.rawValue))
            ink = cut.ink.withUnsafeBytes { Data($0) }
        }

        func cut() throws -> ToneCut {
            let cells = self.cells.compactMap(ToneCut.Cell.init(rawValue:))
            var ink = [Float](repeating: 0, count: self.ink.count / MemoryLayout<Float>.stride)
            _ = ink.withUnsafeMutableBytes { self.ink.copyBytes(to: $0) }
            guard let cut = ToneCut(columns: columns, rows: rows, cells: cells, ink: ink) else { throw Unreadable() }
            return cut
        }
    }
}

extension SheetKind {
    /// A short name that stays the same across versions, for saving.
    var code: String {
        switch self {
        case .grid(let pattern): "grid.\(pattern)"
        case .carbon: "carbon"
        case .tone(let pattern): "tone.\(pattern)"
        }
    }

    init?(code: String) {
        if code == "carbon" { self = .carbon; return }
        if let grid = GridPattern.allCases.first(where: { "grid.\($0)" == code }) { self = .grid(grid); return }
        if let tone = TonePattern.allCases.first(where: { "tone.\($0)" == code }) { self = .tone(tone); return }
        return nil
    }
}
