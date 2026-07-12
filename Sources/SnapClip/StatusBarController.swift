import AppKit

final class StatusBarController: NSObject {
    private let store: HistoryStore
    private let statusItem: NSStatusItem
    private let hotkey = HotkeyManager()

    init(store: HistoryStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            // SF Symbol if available, else text
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
            for (index, item) in items.enumerated() {
                let prefix: String
                switch item.kind {
                case .text: prefix = "Aa"
                case .image: prefix = "🖼"
                }
                let title = "\(index + 1). [\(prefix)] \(item.preview)"
                let mi = NSMenuItem(
                    title: title,
                    action: #selector(pasteItem(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                mi.target = self
                mi.representedObject = item.id
                // Number keys without modifiers when menu is open
                if index < 9 {
                    mi.keyEquivalentModifierMask = []
                }
                menu.addItem(mi)
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

    /// Open history menu (picker via ⌘⇧V).
    func showHistoryMenuAtMouse() {
        rebuildMenu()
        // Open the status-item menu — reliable without an extra panel window.
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

        System Settings → Privacy & Security → Accessibility → enable SnapClip.

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
