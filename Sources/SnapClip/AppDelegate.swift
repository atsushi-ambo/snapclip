import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: HistoryStore!
    private var clipboardMonitor: ClipboardMonitor!
    private var screenshotWatcher: ScreenshotWatcher!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no dock icon
        NSApp.setActivationPolicy(.accessory)

        let maxItems = Int(ProcessInfo.processInfo.environment["SNAPCLIP_MAX_ITEMS"] ?? "") ?? 30
        store = HistoryStore(maxItems: maxItems)

        statusBar = StatusBarController(store: store)

        clipboardMonitor = ClipboardMonitor(store: store)
        clipboardMonitor.onChange = { [weak self] in
            self?.statusBar.rebuildMenu()
        }
        clipboardMonitor.start()

        screenshotWatcher = ScreenshotWatcher(store: store)
        screenshotWatcher.onNewScreenshot = { [weak self] in
            self?.statusBar.rebuildMenu()
        }
        screenshotWatcher.start()

        NSLog("SnapClip ready — history \(maxItems) items, hotkey ⌘⇧V")
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        screenshotWatcher?.stop()
    }
}
