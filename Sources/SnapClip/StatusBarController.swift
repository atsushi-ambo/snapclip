import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private let store: HistoryStore
    private let statusItem: NSStatusItem
    private let hotkey = HotkeyManager()
    private let menu = NSMenu()

    /// Latest N items shown at the top of the menu (not folded).
    private let topVisibleCount = 5

    /// True while the menu is on screen, so background history updates don't
    /// rip items out from under the pointer.
    private var isMenuOpen = false

    /// Item picked from the menu, waiting for menu tracking to finish before we
    /// synthesize the paste keystroke.
    private var pendingPaste: (kind: ClipKind, changeCount: Int)?
    private var searchController: HistorySearchController?
    private var pendingSearch = false
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init(store: HistoryStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "SnapClip") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "⌘V"
            }
            button.toolTip = "SnapClip — clipboard history (⌘⇧V)"
        }

        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openHistoryMenu)
        rememberDestination(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            self?.rememberDestination(notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)
        }

        rebuildMenu()
        hotkey.onHotkey = { [weak self] in
            self?.showHistoryMenuAtMouse()
        }
        hotkey.register()
    }

    /// Refresh the menu contents. The menu also rebuilds itself right before it
    /// opens, so this is skipped while it is showing.
    func rebuildMenu() {
        searchController?.refreshIfVisible()
        statusItem.button?.image = NSImage(systemSymbolName: store.isRecordingPaused ? "pause.circle" : "doc.on.clipboard",
                                           accessibilityDescription: store.isRecordingPaused ? "SnapClip — paused" : "SnapClip")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = store.isRecordingPaused ? "SnapClip — history paused" : "SnapClip — clipboard history (⌘⇧V)"
        guard !isMenuOpen else { return }
        populateMenu()
    }

    private func populateMenu() {
        menu.removeAllItems()

        // Clips come first. A menu opened near the bottom of the screen otherwise
        // shows only the header, and the latest paste sits below the fold.
        let items = store.items
        if items.isEmpty {
            let empty = NSMenuItem(title: "No clips yet — copy something", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let topEnd = min(topVisibleCount, items.count)
            for index in 0..<topEnd {
                menu.addItem(makeClipMenuItem(item: items[index], index: index, assignHotkey: true))
            }

            // One submenu instead of a row per group, so the picker stays short.
            if items.count > topVisibleCount {
                let labelStart = topVisibleCount + 1
                let labelEnd = items.count
                let range = labelStart == labelEnd ? "\(labelStart)" : "\(labelStart)–\(labelEnd)"
                let submenuRoot = NSMenuItem(title: "Older \(range)…", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for index in topVisibleCount..<items.count {
                    submenu.addItem(makeClipMenuItem(item: items[index], index: index, assignHotkey: false))
                }
                // Attach via the item, not menu.setSubmenu(_:for:) — that one
                // silently does nothing unless the item is already in the menu.
                submenuRoot.submenu = submenu
                menu.addItem(submenuRoot)
            }
        }

        menu.addItem(.separator())
        let search = NSMenuItem(title: "Search History…", action: #selector(requestSearch), keyEquivalent: "f")
        search.target = self
        menu.addItem(search)
        if !AXIsProcessTrusted() {
            let permission = NSMenuItem(
                title: "Enable automatic paste…",
                action: #selector(showAccessibilityHelp),
                keyEquivalent: ""
            )
            permission.target = self
            menu.addItem(permission)
        }

        let pause = NSMenuItem(
            title: store.isRecordingPaused ? "Resume History" : "Pause History",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        pause.target = self
        pause.toolTip = store.isRecordingPaused
            ? "Start saving new copies and screenshots to history again."
            : "Stop saving new copies and screenshots. Clips already saved stay usable, and normal copy and paste still work."
        menu.addItem(pause)

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let accessibility = NSMenuItem(
            title: "Accessibility Help…",
            action: #selector(showAccessibilityHelp),
            keyEquivalent: ""
        )
        accessibility.target = self
        menu.addItem(accessibility)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SnapClip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func makeClipMenuItem(item: ClipItem, index: Int, assignHotkey: Bool) -> NSMenuItem {
        let when = DateFormatter.localizedString(
            from: Date(timeIntervalSince1970: item.created), dateStyle: .medium, timeStyle: .short)
        let title: String
        let toolTip: String
        switch item.kind {
        case .text:
            let body = store.previewSource(for: item) ?? item.preview
            title = "Paste \(index + 1)   \(ClipPreview.menuLine(from: body))"
            toolTip = "Copied \(when)\n\(ClipPreview.hoverText(from: body))"
        case .image:
            title = "Paste \(index + 1)   \(item.preview)"
            toolTip = "Copied \(when)"
        }
        let useHotkey = assignHotkey && index < 5
        let mi = NSMenuItem(
            title: title,
            action: #selector(pasteItem(_:)),
            keyEquivalent: useHotkey ? "\(index + 1)" : ""
        )
        mi.target = self
        mi.representedObject = item.id
        mi.toolTip = toolTip
        if item.kind == .image {
            if let thumbnail = ClipThumbnail.menuImage(for: item) {
                // The icon column scales a wide shot down until it disappears.
                // An attachment keeps the thumbnail at the size we chose.
                mi.attributedTitle = imageMenuTitle(title, thumbnail: thumbnail)
            } else {
                NSLog("SnapClip: no thumbnail for %@", item.preview)
            }
        }
        if useHotkey {
            mi.keyEquivalentModifierMask = []
        }
        return mi
    }

    private func imageMenuTitle(_ title: String, thumbnail: NSImage) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let attachment = NSTextAttachment()
        attachment.image = thumbnail
        let y = (font.capHeight - thumbnail.size.height) / 2
        attachment.bounds = NSRect(x: 0, y: y, width: thumbnail.size.width, height: thumbnail.size.height)
        let line = NSMutableAttributedString(attachment: attachment)
        line.append(NSAttributedString(string: "  " + title, attributes: [.font: font]))
        return line
    }

    func showSearchWindow() {
        rememberDestination(NSWorkspace.shared.frontmostApplication)
        presentSearch(destination: lastExternalApplication)
    }

    private func presentSearch(destination: NSRunningApplication?) {
        if searchController == nil { searchController = HistorySearchController(store: store) }
        searchController?.onChoose = { [weak self] item, copyOnly in
            guard let self else { return }
            guard self.store.restoreToPasteboard(item) else {
                PasteHelper.showFailure("This clip could not be loaded. Try copying the original again.")
                return
            }
            self.store.markIgnoreNextChange()
            if copyOnly {
                destination?.activate(options: [])
            } else {
                PasteHelper.pasteRestoredClip(kind: item.kind,
                    changeCount: NSPasteboard.general.changeCount, target: destination)
            }
        }
        searchController?.present()
    }

    @objc private func requestSearch() { pendingSearch = true }

    @objc private func toggleRecording() {
        store.setRecordingPaused(!store.isRecordingPaused)
        rebuildMenu()
    }

    /// Both entry points use one synchronous tracking session. Menu delegate
    /// callbacks can precede item actions, so they must not own paste delivery.
    func showHistoryMenuAtMouse() {
        openHistoryMenu()
    }

    @objc private func openHistoryMenu() {
        guard !isMenuOpen else { return }
        rememberDestination(NSWorkspace.shared.frontmostApplication)
        let destination = lastExternalApplication
        pendingPaste = nil
        pendingSearch = false
        populateMenu()
        isMenuOpen = true
        NSLog("SnapClip: picker opened; destination=%@", destination?.bundleIdentifier ?? "none")
        menu.popUp(positioning: nil, at: popupPoint(), in: nil)
        isMenuOpen = false
        NSLog("SnapClip: picker closed; selected=%@", pendingPaste == nil ? "no" : "yes")
        if pendingSearch {
            pendingSearch = false
            presentSearch(destination: destination)
            return
        }
        guard let item = pendingPaste else { return }
        pendingPaste = nil
        // This executes after popUp returns, including all submenu tracking.
        DispatchQueue.main.async {
            PasteHelper.pasteRestoredClip(kind: item.kind, changeCount: item.changeCount, target: destination)
        }
    }

    /// Top-left of the menu, in screen coordinates. Keeps Paste 1 on screen when
    /// the pointer is near the bottom edge.
    private func popupPoint() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let menuSize = menu.size
        guard menuSize.height > 1, menuSize.width > 1,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else { return mouse }
        let visible = screen.visibleFrame
        var point = mouse
        if menuSize.height >= visible.height {
            point.y = visible.maxY
        } else {
            point.y = min(point.y, visible.maxY)
            if point.y - menuSize.height < visible.minY {
                point.y = visible.minY + menuSize.height
            }
        }
        if point.x + menuSize.width > visible.maxX {
            point.x = max(visible.minX, visible.maxX - menuSize.width)
        } else if point.x < visible.minX {
            point.x = visible.minX
        }
        return point
    }

    private func rememberDestination(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApplication = application
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu, !isMenuOpen else { return }
        populateMenu()
    }

    // MARK: - Actions

    @objc private func pasteItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = store.items.first(where: { $0.id == id }) else {
            NSLog("SnapClip: selection no longer exists in history")
            return
        }
        NSLog("SnapClip: selected %@ clip", item.kind.rawValue)
        // Copy within the action, independently of focus restoration or permission.
        // Automatic paste follows only when the synchronous picker has returned.
        if store.restoreToPasteboard(item) {
            store.markIgnoreNextChange()
            if !NSEvent.modifierFlags.contains(.option) {
                pendingPaste = (item.kind, NSPasteboard.general.changeCount)
            }
            NSLog("SnapClip: selected clip restored to clipboard")
        } else {
            NSLog("SnapClip: selected clip could not be restored")
            DispatchQueue.main.async {
                PasteHelper.showFailure("This clip could not be loaded. Try copying the original again.")
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    @objc private func clearHistory() {
        store.clear()
        rebuildMenu()
    }

    @objc private func showAccessibilityHelp() {
        PasteHelper.showAccessibilityHelp()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
