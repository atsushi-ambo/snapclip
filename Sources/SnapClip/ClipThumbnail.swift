import AppKit
import ImageIO

enum ClipThumbnail {
    /// Widest and tallest a menu preview is allowed to be, in points.
    static let menuMaxSize = NSSize(width: 120, height: 36)
    /// Wide screenshots stay at least this tall so they do not collapse into a line.
    static let menuMinHeight: CGFloat = 22

    private static let cache: NSCache<NSString, SourceImage> = {
        let cache = NSCache<NSString, SourceImage>()
        cache.countLimit = 100
        return cache
    }()

    private final class SourceImage: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// Square-ish thumbnail used by search results.
    static func image(for item: ClipItem, maxPointSize: CGFloat = 28) -> NSImage? {
        guard let cg = sourceImage(for: item) else { return nil }
        let longest = CGFloat(max(cg.width, cg.height))
        guard longest > 1 else { return nil }
        let scale = min(1, maxPointSize / longest)
        return nsImage(cg, size: NSSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale))
    }

    /// Small menu preview. The whole picture is scaled down, and a very wide
    /// shot keeps the leading part at a readable height instead of becoming a hairline.
    static func menuImage(for item: ClipItem) -> NSImage? {
        guard let cg = sourceImage(for: item) else { return nil }
        let pixelW = CGFloat(cg.width)
        let pixelH = CGFloat(cg.height)
        guard pixelW > 1, pixelH > 1 else { return nil }
        let fitted = menuSize(pixelW: pixelW, pixelH: pixelH)
        let aspect = pixelW / pixelH
        let boxAspect = fitted.width / fitted.height
        var used = cg
        if aspect > boxAspect * 1.05 {
            let cropW = max(1, min(pixelW, (pixelH * boxAspect).rounded(.down)))
            if let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: cropW, height: pixelH)) {
                used = cropped
            }
        }
        return nsImage(used, size: fitted)
    }

    static func menuSize(pixelW: CGFloat, pixelH: CGFloat) -> NSSize {
        guard pixelW > 1, pixelH > 1 else { return NSSize(width: 1, height: 1) }
        let aspect = pixelW / pixelH
        var width = menuMaxSize.width
        var height = width / aspect
        if height > menuMaxSize.height {
            height = menuMaxSize.height
            width = height * aspect
        }
        if height < menuMinHeight {
            height = menuMinHeight
            width = min(menuMaxSize.width, height * aspect)
        }
        return NSSize(width: max(1, width.rounded()), height: max(1, height.rounded()))
    }

    private static func nsImage(_ cg: CGImage, size: NSSize) -> NSImage {
        let image = NSImage(cgImage: cg, size: size)
        image.isTemplate = false
        return image
    }

    private static func sourceImage(for item: ClipItem) -> CGImage? {
        let key = item.id as NSString
        if let cached = cache.object(forKey: key) { return cached.image }
        guard HistoryStore.isPathInsideSupportDir(item.absolutePath),
              let source = CGImageSourceCreateWithURL(item.absolutePath as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { return nil }
        cache.setObject(SourceImage(cgImage), forKey: key)
        return cgImage
    }
}
