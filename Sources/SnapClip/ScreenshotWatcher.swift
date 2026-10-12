import Foundation
import AppKit

/// Watches the macOS screenshot folder and adds new images to history + clipboard.
final class ScreenshotWatcher {
    private let store: HistoryStore
    private let directory: URL
    private let pasteboard: NSPasteboard
    private var known = Set<String>()
    private var timer: Timer?

    var onNewScreenshot: (() -> Void)?

    init(store: HistoryStore, directory: URL? = nil, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.store = store
        if let directory {
            self.directory = directory.resolvingSymlinksInPath().standardizedFileURL
        } else {
            self.directory = ScreenshotWatcher.resolveScreenshotDirectory()
        }
        seedKnown()
    }

    func start() {
        // Log only the last path component of the home-relative path to reduce username leakage.
        NSLog("SnapClip: watching screenshots in \(directory.lastPathComponent)/")
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private static func resolveScreenshotDirectory() -> URL {
        if let env = ProcessInfo.processInfo.environment["SNAPCLIP_DIR"], !env.isEmpty {
            let url = URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url.resolvingSymlinksInPath().standardizedFileURL
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.screencapture", "location"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let loc = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !loc.isEmpty {
                let url = URL(fileURLWithPath: (loc as NSString).expandingTildeInPath, isDirectory: true)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return url.resolvingSymlinksInPath().standardizedFileURL
            }
        }
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback.resolvingSymlinksInPath().standardizedFileURL
    }

    private func seedKnown() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in files where isSafeImageFile(url) {
            known.insert(fileKey(url))
        }
    }

    func discardPendingScreenshots() {
        seedKnown()
    }

    func scan() {
        guard !store.isRecordingPaused else {
            seedKnown()
            return
        }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isSymbolicLinkKey,
                .isRegularFileKey
            ],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        // Folder enumeration has no chronological guarantee; the newest capture
        // must be the last image copied when several arrive together.
        let images = files.filter { isSafeImageFile($0) }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left == right ? $0.lastPathComponent < $1.lastPathComponent : left < right
        }
        known.formIntersection(Set(images.map(fileKey)))
        for url in images {
            let key = fileKey(url)
            if known.contains(key) { continue }

            // Wait for write to finish
            guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mdate = vals.contentModificationDate,
                  let size = vals.fileSize, size > 0 else { continue }

            if size > HistoryStore.maxImageBytes {
                known.insert(key)
                NSLog("SnapClip: skipped oversized screenshot (\(size) bytes)")
                continue
            }

            // Brief settle
            if now.timeIntervalSince(mdate) < 0.35 { continue }

            // Retry incomplete files instead of marking them as captured forever.
            guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { continue }
            let existing = store.items.first.flatMap { item -> ClipItem? in
                guard item.kind == .image,
                      (try? Data(contentsOf: item.absolutePath)) == data else { return nil }
                return item
            }
            guard let item = existing ?? store.addImage(from: data, preferredExt: url.pathExtension),
                  store.restoreToPasteboard(item, pasteboard: pasteboard) else { continue }
            store.markIgnoreNextChange(pasteboard: pasteboard)
            known.insert(key)
            NSLog("SnapClip: screenshot copied to clipboard")
            onNewScreenshot?()
        }
    }

    /// Only process real image files that live directly under the watch directory.
    /// Blocks symlinks, path tricks, nested paths, and non-files.
    private func isSafeImageFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") || name.hasPrefix("~") { return false }
        if name.contains("Screen Recording") { return false }
        if name.contains(".tmp") { return false }

        let ext = url.pathExtension.lowercased()
        let allowed: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "gif", "heic", "bmp"]
        guard allowed.contains(ext) else { return false }

        let fm = FileManager.default
        // Reject symlinks before resolving (do not follow into sensitive trees)
        if let vals = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), vals.isSymbolicLink == true {
            return false
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }
        // Must be a regular file (not fifo/socket/device)
        if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]), vals.isRegularFile != true {
            return false
        }

        // Resolved path must be a direct child of the watch directory
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let watch = directory.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.deletingLastPathComponent().path == watch.path else {
            return false
        }

        // Size cap (also enforced again when adding)
        if let attrs = try? fm.attributesOfItem(atPath: resolved.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > HistoryStore.maxImageBytes {
            return false
        }

        return true
    }

    private func fileKey(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? NSNumber,
           let mdate = attrs[.modificationDate] as? Date {
            return "\(path)::\(size)::\(mdate.timeIntervalSince1970)"
        }
        return path
    }
}
