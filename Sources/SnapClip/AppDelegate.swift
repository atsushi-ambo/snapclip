import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: HistoryStore!
    private var clipboardMonitor: ClipboardMonitor!
    private var screenshotWatcher: ScreenshotWatcher!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no dock icon
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                    ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu

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
        store.onRecordingStateChange = { [weak self] in
            self?.clipboardMonitor.discardCurrentClipboard()
            self?.screenshotWatcher.discardPendingScreenshots()
            self?.statusBar.rebuildMenu()
        }

        NSLog("SnapClip: Accessibility permission %@", AXIsProcessTrusted() ? "granted" : "missing")
        NSLog("SnapClip ready — history \(maxItems) items, hotkey ⌘⇧V")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar.showSearchWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        screenshotWatcher?.stop()
    }
}
