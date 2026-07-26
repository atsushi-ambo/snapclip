import Foundation
import AppKit

enum ClipKind: String, Codable {
    case text
    case image
}

struct ClipItem: Codable, Identifiable, Equatable {
    let id: String
    let kind: ClipKind
    let preview: String
    let created: TimeInterval
    /// Relative path under Application Support/SnapClip/ (must stay under that root).
    let relativePath: String

    var absolutePath: URL {
        HistoryStore.supportDir.appendingPathComponent(relativePath)
    }
}

/// Persists the last N clipboard items (text + images) on disk.
final class HistoryStore {
    /// Max UTF-8 bytes accepted for a single text clip (images use a separate 50 MB cap).
    static let maxTextBytes = 2 * 1024 * 1024
    /// Max bytes for a single image clip.
    static let maxImageBytes = 50 * 1024 * 1024

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SnapClip", isDirectory: true)
        let items = dir.appendingPathComponent("items", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        // Owner-only dirs so other local accounts cannot list UUID filenames.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: items.path)
        return dir
    }()

    private let indexURL = HistoryStore.supportDir.appendingPathComponent("history.json")
    private let maxItems: Int
    private let lock = NSLock()
    private(set) var items: [ClipItem] = []

    /// When we paste from history we set the pasteboard — ignore that echo.
    private var ignoreNextPasteboardChange = false

    init(maxItems: Int = 30) {
        self.maxItems = max(1, min(maxItems, 100))
        load()
    }

    func markIgnoreNextChange() {
        ignoreNextPasteboardChange = true
    }

    func shouldIgnoreChange() -> Bool {
        if ignoreNextPasteboardChange {
            ignoreNextPasteboardChange = false
            return true
        }
        return false
    }

    @discardableResult
    func addText(_ text: String) -> ClipItem? {
        // Keep internal newlines; only strip a single trailing newline from pbcopy-style data
        var trimmed = text
        if trimmed.hasSuffix("\r\n") {
            trimmed = String(trimmed.dropLast(2))
        } else if trimmed.hasSuffix("\n") || trimmed.hasSuffix("\r") {
            trimmed = String(trimmed.dropLast())
        }
        guard !trimmed.isEmpty else { return nil }
        // Bound disk use / accidental giant pastes
        guard trimmed.utf8.count <= Self.maxTextBytes else {
            NSLog("SnapClip: skipped text clip over \(Self.maxTextBytes) bytes")
            return nil
        }
        // Dedupe consecutive identical text
        if let first = items.first, first.kind == .text, first.preview == preview(for: trimmed) {
            // Still check full content
            if let existing = try? String(contentsOf: first.absolutePath, encoding: .utf8), existing == trimmed {
                return nil
            }
        }
        let id = UUID().uuidString
        let rel = "items/\(id).txt"
        guard Self.isSafeRelativePath(rel) else { return nil }
        let url = HistoryStore.supportDir.appendingPathComponent(rel)
        do {
            try trimmed.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("SnapClip: failed to save text: \(error)")
            return nil
        }
        let item = ClipItem(
            id: id,
            kind: .text,
            preview: preview(for: trimmed),
            created: Date().timeIntervalSince1970,
            relativePath: rel
        )
        insert(item)
        return item
    }

    @discardableResult
    func addImage(from data: Data, preferredExt: String = "png") -> ClipItem? {
        guard !data.isEmpty, data.count <= Self.maxImageBytes else { return nil }
        // Dedupe consecutive identical images by size + prefix hash
        if let first = items.first, first.kind == .image,
           let existing = try? Data(contentsOf: first.absolutePath),
           existing == data {
            return nil
        }
        let id = UUID().uuidString
        let ext = Self.sanitizedImageExtension(preferredExt)
        let rel = "items/\(id).\(ext)"
        guard Self.isSafeRelativePath(rel) else { return nil }
        let url = HistoryStore.supportDir.appendingPathComponent(rel)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("SnapClip: failed to save image: \(error)")
            return nil
        }
        let sizeLabel: String
        if let img = NSImage(data: data) {
            let s = img.size
            sizeLabel = "Image \(Int(s.width))×\(Int(s.height))"
        } else {
            sizeLabel = "Image"
        }
        let item = ClipItem(
            id: id,
            kind: .image,
            preview: sizeLabel,
            created: Date().timeIntervalSince1970,
            relativePath: rel
        )
        insert(item)
        return item
    }

    @discardableResult
    func addImage(fromFile fileURL: URL) -> ClipItem? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension
        return addImage(from: data, preferredExt: ext)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        for item in items {
            let url = item.absolutePath
            if Self.isPathInsideSupportDir(url) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        items = []
        saveUnlocked()
    }

    func remove(id: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let item = items.remove(at: idx)
            let url = item.absolutePath
            if Self.isPathInsideSupportDir(url) {
                try? FileManager.default.removeItem(at: url)
            }
            saveUnlocked()
        }
    }

    /// Put item on the pasteboard (does not trigger re-history if markIgnoreNextChange was set).
    func restoreToPasteboard(_ item: ClipItem) -> Bool {
        guard Self.isPathInsideSupportDir(item.absolutePath) else {
            NSLog("SnapClip: refused to restore item outside support dir")
            return false
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            guard let text = try? String(contentsOf: item.absolutePath, encoding: .utf8) else { return false }
            return pb.setString(text, forType: .string)
        case .image:
            guard let data = try? Data(contentsOf: item.absolutePath) else { return false }
            guard let img = NSImage(data: data) else {
                pb.declareTypes([.png], owner: nil)
                return pb.setData(data, forType: .png)
            }
            // Offer both public.png and public.tiff. Writing the NSImage alone yields
            // TIFF only, which some readers (terminal TUIs looking for public.png)
            // never pick up.
            let isPNG = item.absolutePath.pathExtension.lowercased() == "png"
            let tiff = img.tiffRepresentation
            let png: Data? = isPNG ? data : tiff
                .flatMap { NSBitmapImageRep(data: $0) }
                .flatMap { $0.representation(using: .png, properties: [:]) }

            var types: [NSPasteboard.PasteboardType] = []
            if png != nil { types.append(.png) }
            if tiff != nil { types.append(.tiff) }
            guard !types.isEmpty else { return false }
            pb.declareTypes(types, owner: nil)

            var ok = false
            if let png { ok = pb.setData(png, forType: .png) || ok }
            if let tiff { ok = pb.setData(tiff, forType: .tiff) || ok }
            return ok
        }
    }

    // MARK: - Path safety

    /// Only allow relative paths like `items/<uuid>.<ext>` with no traversal.
    static func isSafeRelativePath(_ relativePath: String) -> Bool {
        let path = relativePath
        guard !path.isEmpty else { return false }
        guard !path.hasPrefix("/") else { return false }
        guard !path.contains("\0") else { return false }
        // Reject traversal and backslashes
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { return false }
        guard parts.allSatisfy({ !$0.contains("\\") && !$0.isEmpty }) else { return false }
        // Must live under items/
        guard parts.count == 2, parts[0] == "items" else { return false }
        let file = parts[1]
        // UUID-ish name + simple extension (letters only)
        guard let dot = file.lastIndex(of: ".") else { return false }
        let name = String(file[..<dot])
        let ext = String(file[file.index(after: dot)...]).lowercased()
        guard !name.isEmpty, name.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return false }
        guard ext.range(of: "^[a-z0-9]{1,8}$", options: .regularExpression) != nil else { return false }
        return isPathInsideSupportDir(supportDir.appendingPathComponent(path))
    }

    static func isPathInsideSupportDir(_ url: URL) -> Bool {
        let root = supportDir.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        if candidate == root { return false } // must be a file under root, not the dir itself
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return candidate.hasPrefix(prefix)
    }

    private static func sanitizedImageExtension(_ preferred: String) -> String {
        let ext = preferred.lowercased()
        let allowed: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "gif", "heic", "bmp"]
        return allowed.contains(ext) ? ext : "png"
    }

    // MARK: - Private

    private func insert(_ item: ClipItem) {
        lock.lock()
        defer { lock.unlock() }
        items.insert(item, at: 0)
        while items.count > maxItems {
            let dropped = items.removeLast()
            if Self.isPathInsideSupportDir(dropped.absolutePath) {
                try? FileManager.default.removeItem(at: dropped.absolutePath)
            }
        }
        saveUnlocked()
    }

    private func preview(for text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count <= 60 { return oneLine.isEmpty ? "(empty)" : oneLine }
        let idx = oneLine.index(oneLine.startIndex, offsetBy: 60)
        return String(oneLine[..<idx]) + "…"
    }

    private func load() {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else {
            items = []
            return
        }
        // Drop missing files and anything that escapes the support directory
        let filtered = decoded.filter { item in
            guard Self.isSafeRelativePath(item.relativePath) else {
                NSLog("SnapClip: dropped history entry with unsafe path")
                return false
            }
            return FileManager.default.fileExists(atPath: item.absolutePath.path)
        }
        items = filtered
        if items.count != decoded.count {
            saveUnlocked()
        }
    }

    private func saveUnlocked() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
        } catch {
            NSLog("SnapClip: failed to save index: \(error)")
        }
    }
}
