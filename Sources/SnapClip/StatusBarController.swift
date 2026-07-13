import AppKit

final class StatusBarController: NSObject {
    private let store: HistoryStore
    private let statusItem: NSStatusItem
    private let hotkey = HotkeyManager()

    /// Latest N items shown at the top of the menu (not folded).
    private let topVisibleCount = 5
    /// Older items grouped into submenus of this size (6–10, 11–15, …).
    private let foldGroupSize = 5

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

        rebuildMenu()
        hotkey.onHotkey = { [weak self] in
            self?.showHistoryMenuAtMouse()
        }
        hotkey.register()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "SnapClip History", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let hint = NSMenuItem(title: "Paste picker: ⌘⇧V", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let items = store.items
        if items.isEmpty {
            let empty = NSMenuItem(title: "No clips yet — copy something", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            // Latest 5 always visible
            let topEnd = min(topVisibleCount, items.count)
            for index in 0..<topEnd {
                menu.addItem(makeClipMenuItem(item: items[index], index: index, assignHotkey: true))
            }

            // Fold remaining into submenus: 6–10, 11–15, …
            if items.count > topVisibleCount {
                menu.addItem(.separator())
                var start = topVisibleCount
                while start < items.count {
                    let end = min(start + foldGroupSize, items.count) // exclusive index
                    let labelStart = start + 1
                    let labelEnd = end
                    let submenuRoot = NSMenuItem(
                        title: "Older \(labelStart)–\(labelEnd)…",
                        action: nil,
                        keyEquivalent: ""
                    )
                    let submenu = NSMenu()
                    submenu.autoenablesItems = false
                    for index in start..<end {
                        submenu.addItem(makeClipMenuItem(item: items[index], index: index, assignHotkey: false))
                    }
                    menu.setSubmenu(submenu, for: submenuRoot)
                    menu.addItem(submenuRoot)
                    start = end
                }
            }
        }

        menu.addItem(.separator())

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

        statusItem.menu = menu
    }

    private func makeClipMenuItem(item: ClipItem, index: Int, assignHotkey: Bool) -> NSMenuItem {
        let prefix: String
        switch item.kind {
        case .text: prefix = "Aa"
        case .image: prefix = "🖼"
        }
        let title = "\(index + 1). [\(prefix)] \(item.preview)"
        let useHotkey = assignHotkey && index < 5
        let mi = NSMenuItem(
            title: title,
            action: #selector(pasteItem(_:)),
            keyEquivalent: useHotkey ? "\(index + 1)" : ""
        )
        mi.target = self
        mi.representedObject = item.id
        if useHotkey {
            mi.keyEquivalentModifierMask = []
        }
        return mi
    }

    /// Open history menu (picker via ⌘⇧V).
    func showHistoryMenuAtMouse() {
        rebuildMenu()
        statusItem.button?.performClick(nil)
    }

    @objc private func pasteItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = store.items.first(where: { $0.id == id }) else { return }
        PasteHelper.paste(item: item, store: store)
    }

    @objc private func clearHistory() {
        store.clear()
        rebuildMenu()
    }

    @objc private func showAccessibilityHelp() {
        let alert = NSAlert()
        alert.messageText = "Allow SnapClip to paste"
        alert.informativeText = """
        To paste into other apps after you pick a history item, macOS needs Accessibility permission for SnapClip.

        System Settings → Privacy & Security → Accessibility → click +, choose ~/Applications/SnapClip.app, turn it on.

        You can still copy items to the clipboard from the menu without this; only automatic Cmd+V needs it.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
