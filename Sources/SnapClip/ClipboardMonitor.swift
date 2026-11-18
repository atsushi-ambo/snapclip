import AppKit
import Foundation

final class ClipboardMonitor {
    private let store: HistoryStore
    private var lastChangeCount: Int = -1
    private var timer: Timer?

    var onChange: (() -> Void)?

    init(store: HistoryStore) {
        self.store = store
    }

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.tick()
        }
        captureCurrent(force: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Pausing/resuming must not save whatever was copied during the pause.
    func discardCurrentClipboard() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func tick() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if store.shouldIgnoreChange(changeCount: count) {
            return
        }
        captureCurrent(force: false)
    }

    private func captureCurrent(force: Bool) {
        let pb = NSPasteboard.general

        if let imgData = readImageData(from: pb) {
            if store.addImage(from: imgData) != nil {
                onChange?()
            }
            return
        }

        if let str = pb.string(forType: .string), !str.isEmpty {
            if str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            if store.addText(str) != nil {
                onChange?()
            }
            return
        }

        if force {
        }
    }

    private func readImageData(from pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png), !png.isEmpty {
            return png
        }
        if let tiff = pb.data(forType: .tiff), !tiff.isEmpty {
            // Normalize to PNG for compact storage
            if let img = NSImage(data: tiff),
                let tiffRep = img.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiffRep),
                let png = rep.representation(using: .png, properties: [:])
            {
                return png
            }
            return tiff
        }
        // Some apps only expose NSImage via readObjects
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
            let img = images.first,
            let tiff = img.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        {
            return png
        }
        return nil
    }
}
