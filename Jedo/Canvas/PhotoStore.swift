import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The pictures laid on the desk as prints, kept beside the drawing in the
/// app's own folder and never sent anywhere.
enum PhotoStore {
    /// Plenty for a 152 mm print on any iPad screen.
    static let maxPixels = 2000
    /// Enough to take colour from.
    static let samplePixels = 600

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("photos")
    }

    private static func url(_ id: String) -> URL { folder.appendingPathComponent("\(id).jpg") }

    /// Takes in a picture: shrunk, turned upright, saved. Nil if it can't be read.
    @MainActor
    static func add(_ data: Data) -> PhotoRef? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = thumbnail(source, maxPixels: maxPixels) else { return nil }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let out = CGImageDestinationCreateWithURL(url(id) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(out) else { return nil }
        images[id] = image
        return PhotoRef(id: id, pixelWidth: image.width, pixelHeight: image.height)
    }

    /// Takes in the first page of a PDF as a print at its real size (an A4
    /// page comes out 210 × 297 mm). Nil if it can't be read.
    @MainActor
    static func addPDF(at url: URL) -> PhotoRef? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        var box = page.getBoxRect(.cropBox)
        if page.rotationAngle % 180 != 0 { box.size = CGSize(width: box.height, height: box.width) }
        guard box.width > 1, box.height > 1 else { return nil }
        // Sharp enough to read at real size, never more pixels than a photo.
        let scale = min(200.0 / 72, CGFloat(maxPixels + 600) / max(box.width, box.height))
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // The page's own transform never enlarges, so fit it at 1:1 and scale the context.
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: box.size), rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { return nil }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let out = CGImageDestinationCreateWithURL(self.url(id) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(out) else { return nil }
        images[id] = image
        let mm = 25.4 / 72
        return PhotoRef(id: id, widthMM: (Double(box.width) * mm).rounded(), heightMM: (Double(box.height) * mm).rounded())
    }

    private static func thumbnail(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary)
    }

    @MainActor private static var images: [String: CGImage] = [:]
    private static let pixelLock = NSLock()
    nonisolated(unsafe) private static var pixelCache: [String: PhotoPixels] = [:]

    @MainActor
    static func image(_ id: String) -> CGImage? {
        if let image = images[id] { return image }
        guard let source = CGImageSourceCreateWithURL(url(id) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[id] = image
        return image
    }

    /// The picture's colours, small, for carbon made of it.
    static func pixels(_ id: String) -> PhotoPixels? {
        pixelLock.lock()
        defer { pixelLock.unlock() }
        if let cached = pixelCache[id] { return cached }
        guard let source = CGImageSourceCreateWithURL(url(id) as CFURL, nil),
              let image = thumbnail(source, maxPixels: samplePixels) else { return nil }
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        let pixels = PhotoPixels(width: w, height: h, rgba: rgba)
        pixelCache[id] = pixels
        return pixels
    }

    /// Lets go of pictures nothing on the desk uses any more. One just taken
    /// in may not be in the drawing being written yet, so recent ones stay.
    static func keepOnly(_ ids: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where !ids.contains(file.deletingPathExtension().lastPathComponent) {
            let made = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date.now.timeIntervalSince(made) > 300 { try? FileManager.default.removeItem(at: file) }
        }
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}
