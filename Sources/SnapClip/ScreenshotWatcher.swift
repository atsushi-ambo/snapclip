import Foundation
import AppKit

/// Watches the macOS screenshot folder and adds new images to history + clipboard.
final class ScreenshotWatcher {
    private let store: HistoryStore
    private let directory: URL
    private var known = Set<String>()
    private var timer: Timer?
    private let maxAgeOnDiscover: TimeInterval = 8

    var onNewScreenshot: (() -> Void)?

    init(store: HistoryStore, directory: URL? = nil) {
        self.store = store
        if let directory {
            self.directory = directory
        } else {
            self.directory = ScreenshotWatcher.resolveScreenshotDirectory()
        }
        seedKnown()
    }

    func start() {
        NSLog("SnapClip: watching screenshots in \(directory.path)")
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
            return url
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
                return url
            }
        }
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    private func seedKnown() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }
        for url in files where isImage(url) {
            known.insert(fileKey(url))
        }
    }

    private func scan() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        for url in files where isImage(url) {
            let key = fileKey(url)
            if known.contains(key) { continue }

            // Wait for write to finish
            guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mdate = vals.contentModificationDate,
                  let size = vals.fileSize, size > 0 else { continue }

            if now.timeIntervalSince(mdate) > maxAgeOnDiscover {
                known.insert(key)
                continue
            }
            // Brief settle
            if now.timeIntervalSince(mdate) < 0.35 { continue }

            known.insert(key)
            if let item = store.addImage(fromFile: url) {
                // Also put on pasteboard for immediate Cmd+V
                store.markIgnoreNextChange()
                _ = store.restoreToPasteboard(item)
                NSLog("SnapClip: screenshot captured → \(url.lastPathComponent)")
                onNewScreenshot?()
            }
        }
    }

    private func isImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let allowed: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "gif", "heic", "bmp"]
        if url.lastPathComponent.hasPrefix(".") { return false }
        if url.lastPathComponent.contains("Screen Recording") { return false }
        // Skip symlinks
        if let vals = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), vals.isSymbolicLink == true {
            return false
        }
        return allowed.contains(ext)
    }

    private func fileKey(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? NSNumber,
           let mdate = attrs[.modificationDate] as? Date {
            return "\(path)::\(size)::\(Int(mdate.timeIntervalSince1970))"
        }
        return path
    }
}
