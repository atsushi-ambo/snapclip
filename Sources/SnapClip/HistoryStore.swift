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
    /// Relative path under Application Support/SnapClip/
    let relativePath: String

    var absolutePath: URL {
        HistoryStore.supportDir.appendingPathComponent(relativePath)
    }
}

/// Persists the last N clipboard items (text + images) on disk.
final class HistoryStore {
    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SnapClip", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("items", isDirectory: true),
            withIntermediateDirectories: true
        )
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
        // Dedupe consecutive identical text
        if let first = items.first, first.kind == .text, first.preview == preview(for: trimmed) {
            // Still check full content
            if let existing = try? String(contentsOf: first.absolutePath, encoding: .utf8), existing == trimmed {
                return nil
            }
        }
        let id = UUID().uuidString
        let rel = "items/\(id).txt"
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
        guard !data.isEmpty, data.count <= 50 * 1024 * 1024 else { return nil }
        // Dedupe consecutive identical images by size + prefix hash
        if let first = items.first, first.kind == .image,
           let existing = try? Data(contentsOf: first.absolutePath),
           existing == data {
            return nil
        }
        let id = UUID().uuidString
        let ext = preferredExt.lowercased()
        let rel = "items/\(id).\(ext)"
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
            try? FileManager.default.removeItem(at: item.absolutePath)
        }
        items = []
        saveUnlocked()
    }

    func remove(id: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let item = items.remove(at: idx)
            try? FileManager.default.removeItem(at: item.absolutePath)
            saveUnlocked()
        }
    }

    /// Put item on the pasteboard (does not trigger re-history if markIgnoreNextChange was set).
    func restoreToPasteboard(_ item: ClipItem) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            guard let text = try? String(contentsOf: item.absolutePath, encoding: .utf8) else { return false }
            return pb.setString(text, forType: .string)
        case .image:
            guard let data = try? Data(contentsOf: item.absolutePath) else { return false }
            if let img = NSImage(data: data) {
                return pb.writeObjects([img])
            }
            // Fallback: raw PNG
            pb.setData(data, forType: .png)
            return true
        }
    }

    // MARK: - Private

    private func insert(_ item: ClipItem) {
        lock.lock()
        defer { lock.unlock() }
        items.insert(item, at: 0)
        while items.count > maxItems {
            let dropped = items.removeLast()
            try? FileManager.default.removeItem(at: dropped.absolutePath)
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
        // Drop missing files
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.absolutePath.path) }
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
