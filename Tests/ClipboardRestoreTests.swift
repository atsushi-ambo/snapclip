import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let preferenceName = "SnapClipTests-\(UUID().uuidString)"
let preferences = UserDefaults(suiteName: preferenceName)!
defer { preferences.removePersistentDomain(forName: preferenceName) }
let store = HistoryStore(preferences: preferences)
let pb = NSPasteboard.withUniqueName()
defer { pb.releaseGlobally() }
var fixtures: [URL] = []
defer { for url in fixtures { try? FileManager.default.removeItem(at: url) } }
func item(_ kind: ClipKind, ext: String, data: Data) throws -> ClipItem {
    let id = UUID().uuidString
    let clip = ClipItem(id: id, kind: kind, preview: "test", created: 0, relativePath: "items/\(id).\(ext)")
    try data.write(to: clip.absolutePath)
    fixtures.append(clip.absolutePath)
    return clip
}
let text = "SnapClip regression: 日本語\nsecond line"
let clip = try item(.text, ext: "txt", data: Data(text.utf8))
precondition(store.restoreToPasteboard(clip, pasteboard: pb))
precondition(pb.string(forType: .string) == text)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let pixels = bitmap.bitmapData!
for y in 0..<2 {
    for x in 0..<2 {
        let offset = y * bitmap.bytesPerRow + x * 4
        pixels[offset] = 255
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 255
    }
}
for ext in ["png", "tiff"] {
    let data = ext == "png" ? bitmap.representation(using: .png, properties: [:])! : bitmap.tiffRepresentation!
    let image = try item(.image, ext: ext, data: data)
    precondition(store.restoreToPasteboard(image, pasteboard: pb))
    precondition(NSImage(data: pb.data(forType: .png)!) != nil)
    precondition(NSImage(data: pb.data(forType: .tiff)!) != nil)
    precondition(pb.string(forType: .string) == nil, "Images must replace previous text")
}
pb.clearContents()
pb.setString("preserved", forType: .string)
try FileManager.default.removeItem(at: clip.absolutePath)
precondition(!store.restoreToPasteboard(clip, pasteboard: pb))
precondition(pb.string(forType: .string) == "preserved", "Unreadable clip must not erase clipboard")
print("PASS: text round trip; PNG and TIFF image pasteboard formats; failed restore preserves clipboard")

// Test builds use a unique temporary history directory, never the user's history.
defer { try? FileManager.default.removeItem(at: HistoryStore.supportDir) }
let code = "line one\r\nline two\r\n"
let saved = store.addText(code)!
precondition(store.restoreToPasteboard(saved, pasteboard: pb))
precondition(pb.string(forType: .string) == code, "Preserve trailing CRLF")
store.markIgnoreNextChange(pasteboard: pb)
precondition(store.shouldIgnoreChange(changeCount: pb.changeCount), "Ignore our exact restore")
store.markIgnoreNextChange(pasteboard: pb)
pb.clearContents()
pb.setString("a newer user copy", forType: .string)
precondition(!store.shouldIgnoreChange(changeCount: pb.changeCount), "Never drop the next real copy")
precondition(store.addImage(from: Data("not an image".utf8)) == nil)
let broken = try item(.image, ext: "png", data: Data("not an image".utf8))
precondition(!store.restoreToPasteboard(broken, pasteboard: pb))
precondition(pb.string(forType: .string) == "a newer user copy")

let watchDir = HistoryStore.supportDir.appendingPathComponent("watch", isDirectory: true)
try FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)
let png = bitmap.representation(using: .png, properties: [:])!
let oldFile = watchDir.appendingPathComponent("old.png")
try png.write(to: oldFile)
let watcher = ScreenshotWatcher(store: store, directory: watchDir, pasteboard: pb)
var captures = 0
watcher.onNewScreenshot = { captures += 1 }
watcher.scan()
precondition(captures == 0, "Do not capture pre-existing files")
let delayed = watchDir.appendingPathComponent("delayed.png")
try png.write(to: delayed)
try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30)], ofItemAtPath: delayed.path)
watcher.scan()
precondition(captures == 1 && pb.data(forType: .png) == png, "Capture late screenshot saves")
let count = store.items.count
pb.clearContents()
pb.setString("temporary text", forType: .string)
let duplicate = watchDir.appendingPathComponent("duplicate.png")
try png.write(to: duplicate)
try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2)], ofItemAtPath: duplicate.path)
watcher.scan()
precondition(captures == 2 && pb.data(forType: .png) == png, "Duplicate screenshot must still copy")
precondition(store.items.count == count, "Duplicate screenshot must not duplicate history")
let partial = watchDir.appendingPathComponent("partial.png")
try Data("unfinished".utf8).write(to: partial)
try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2)], ofItemAtPath: partial.path)
watcher.scan()
precondition(captures == 2, "Wait for a valid image")
try png.write(to: partial)
try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2)], ofItemAtPath: partial.path)
watcher.scan()
precondition(captures == 3, "Retry unfinished screenshot")
let link = watchDir.appendingPathComponent("symlink.png")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: oldFile)
watcher.scan()
precondition(captures == 3, "Ignore symbolic links")
print("PASS: exact text; copy-change tracking; invalid images; delayed, duplicate and incomplete screenshots; symlink exclusion")

let longText = String(repeating: "prefix ", count: 20) + "Café SearchNeedle 日本語"
let searchable = store.addText(longText)!
precondition(!searchable.preview.contains("SearchNeedle"))
precondition(HistorySearch.filter(store.items, query: "searchneedle", kind: .text).map(\.id) == [searchable.id])
precondition(HistorySearch.filter(store.items, query: "cafe", kind: nil).map(\.id) == [searchable.id])
precondition(HistorySearch.filter(store.items, query: "日本語", kind: nil).map(\.id) == [searchable.id])
precondition(HistorySearch.filter(store.items, query: "searchneedle", kind: .image).isEmpty)
precondition(HistorySearch.filter(store.items, query: "  ", kind: nil) == store.items)
precondition(HistorySearch.filter(store.items, query: "zz-no-results", kind: nil).isEmpty)
let beforePause = store.items
var pauseTransitions = 0
store.onRecordingStateChange = { pauseTransitions += 1; watcher.discardPendingScreenshots() }
store.setRecordingPaused(true)
precondition(store.addText("must not save") == nil)
precondition(store.addImage(from: png) == nil)
let pausedFile = watchDir.appendingPathComponent("paused.png")
try png.write(to: pausedFile)
try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2)], ofItemAtPath: pausedFile.path)
watcher.scan()
precondition(store.items == beforePause && captures == 3)
precondition(store.restoreToPasteboard(searchable, pasteboard: pb), "Existing clips work while paused")
let restarted = HistoryStore(preferences: preferences)
precondition(restarted.isRecordingPaused, "Pause survives restart")
store.setRecordingPaused(false)
watcher.scan()
precondition(captures == 3, "Do not replay screenshots from the pause")
precondition(store.addText("new copy after resume") != nil)
precondition(pauseTransitions == 2)
print("PASS: full-text and Unicode search; type filters; persistent pause; paused screenshots stay excluded; resume")

precondition(HistorySearch.excerpt(for: searchable, query: "searchneedle").contains("SearchNeedle"))
precondition(HistorySearch.excerpt(for: searchable, query: "").contains("prefix"))
let menuLine = ClipPreview.menuLine(from: store.previewSource(for: searchable)!)
precondition(menuLine.contains("…") && menuLine.hasSuffix("日本語"))
precondition(menuLine.count <= ClipPreview.menuLimit)
precondition(ClipPreview.menuLine(from: "") == "(empty)")
precondition(ClipPreview.menuLine(from: "   \n\t") == "(empty)")
precondition(ClipPreview.menuLine(from: String(repeating: "あ", count: 28)) == String(repeating: "あ", count: 28))
let over = ClipPreview.menuLine(from: String(repeating: "あ", count: 29))
precondition(over.count <= ClipPreview.menuLimit && over.contains("…"))
precondition(ClipPreview.menuLine(from: "OPENING LINE\nmiddle\nCLOSING LINE") == "OPENING LINE…CLOSING LINE")
let longLast = ClipPreview.menuLine(from: "START\n" + String(repeating: "あ", count: 30) + "終わり")
precondition(longLast.hasPrefix("START…") && longLast.hasSuffix("終わり") && longLast.count <= ClipPreview.menuLimit)
for sample in ["a", "a\nb", "Café\n日本語", String(repeating: "x", count: 500), "line\n\n\nend"] {
    precondition(ClipPreview.menuLine(from: sample).count <= ClipPreview.menuLimit)
}
print("PASS: menu lines keep the start and end of long and multiline clips")

func solidPNG(width: Int, height: Int, left: NSColor, right: NSColor) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let leftRGB = left.usingColorSpace(.deviceRGB)!
    let rightRGB = right.usingColorSpace(.deviceRGB)!
    for y in 0..<height {
        for x in 0..<width {
            let color = x < width / 2 ? leftRGB : rightRGB
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let offset = y * rep.bytesPerRow + x * 4
            rep.bitmapData![offset] = UInt8(r * 255)
            rep.bitmapData![offset + 1] = UInt8(g * 255)
            rep.bitmapData![offset + 2] = UInt8(b * 255)
            rep.bitmapData![offset + 3] = 255
        }
    }
    return rep.representation(using: .png, properties: [:])!
}
func red(at image: NSImage, xFraction: CGFloat) -> CGFloat {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return -1 }
    let x = min(cg.width - 1, max(0, Int(CGFloat(cg.width) * xFraction)))
    let y = cg.height / 2
    guard let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return -1 }
    let info = cg.bitmapInfo
    let alpha = info.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
    let offset = y * cg.bytesPerRow + x * 4
    let redIndex = alpha == CGImageAlphaInfo.premultipliedFirst.rawValue
        || alpha == CGImageAlphaInfo.first.rawValue
        || alpha == CGImageAlphaInfo.noneSkipFirst.rawValue ? 1 : 0
    return CGFloat(bytes[offset + redIndex]) / 255
}
let wideShot = try item(.image, ext: "png", data: solidPNG(width: 200, height: 40, left: .red, right: .blue))
let widePreview = ClipThumbnail.menuImage(for: wideShot)!
precondition(widePreview.size.width <= ClipThumbnail.menuMaxSize.width)
precondition(widePreview.size.height >= ClipThumbnail.menuMinHeight)
precondition(widePreview.size.width > widePreview.size.height, "Wide shots stay wide")
precondition(red(at: widePreview, xFraction: 0.1) > 0.7, "Leading side of the screenshot stays visible")
precondition(red(at: widePreview, xFraction: 0.9) < 0.3, "The far side stays visible when it fits")
let banner = try item(.image, ext: "png", data: solidPNG(width: 800, height: 20, left: .red, right: .blue))
let bannerPreview = ClipThumbnail.menuImage(for: banner)!
precondition(bannerPreview.size.height >= ClipThumbnail.menuMinHeight)
precondition(bannerPreview.size.width <= ClipThumbnail.menuMaxSize.width)
precondition(red(at: bannerPreview, xFraction: 0.85) > 0.7, "A very wide shot shows its leading part, not a hairline")
let square = ClipThumbnail.menuSize(pixelW: 500, pixelH: 500)
precondition(square.width <= ClipThumbnail.menuMaxSize.height + 0.5 && square.height <= ClipThumbnail.menuMaxSize.height + 0.5)
print("PASS: menu thumbnails keep wide screenshots recognizable")
