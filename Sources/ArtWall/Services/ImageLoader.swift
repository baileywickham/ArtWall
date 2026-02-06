import AppKit
import ImageIO

final class ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func thumbnail(for url: URL, maxPixels: Int = 400) -> NSImage? {
        let nsurl = url as NSURL
        if let cached = cache.object(forKey: nsurl) {
            return cached
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: nsurl)
        return image
    }

    func fullImage(for url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }
}
