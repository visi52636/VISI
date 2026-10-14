import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessing {
    /// Loads an image from disk, downscaled so its longest side is at most `maxPixelSize`.
    /// GPUs limit texture size (typically 8192 or 16384 px), so large panoramas must be reduced for display.
    static func downsampledImage(at url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Returns JPEG data for a thumbnail of the image at `url`.
    static func thumbnailData(for url: URL, maxPixelSize: Int = 600) -> Data? {
        downsampledImage(at: url, maxPixelSize: maxPixelSize)?.jpegData(compressionQuality: 0.8)
    }

    /// Best-effort file extension for raw image data (keeps HEIC/PNG originals intact).
    static func fileExtension(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier),
              let ext = type.preferredFilenameExtension else {
            return "jpg"
        }
        return ext
    }

    /// Renders the first page of a PDF (e.g. an architectural floor plan) to PNG data.
    static func renderFirstPDFPage(_ data: Data, maxPixelSize: CGFloat = 4096) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = maxPixelSize / max(box.width, box.height)
        let size = CGSize(width: box.width * scale, height: box.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -box.minX, y: -box.minY)
            cg.drawPDFPage(page)
        }
        return image.pngData()
    }

    static func isPDF(_ data: Data) -> Bool {
        data.prefix(5) == Data("%PDF-".utf8)
    }

    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}
