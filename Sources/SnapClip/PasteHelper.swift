import AppKit
import Carbon.HIToolbox

enum PasteHelper {
    /// Terminal emulators that swallow Cmd+V as "paste text" and never see image data.
    /// TUI apps running inside them (Claude Code, etc.) expect Ctrl+V for images.
    private static let terminalBundleIDs: Set<String> = [
        "com.mitchellh.ghostty",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
    ]

    /// Set pasteboard from history item and simulate a paste into the frontmost app.
    static func paste(item: ClipItem, store: HistoryStore) {
        store.markIgnoreNextChange()
        guard store.restoreToPasteboard(item) else {
            NSLog("SnapClip: failed to restore item to pasteboard")
            return
        }

        // Images into a terminal need Ctrl+V — Cmd+V there pastes text only,
        // so an image-only clipboard would paste nothing at all.
        let useControl = item.kind == .image && frontmostIsTerminal()

        // Give the pasteboard a moment, then send the keystroke
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste(useControl: useControl)
        }
    }

    static func simulateCommandV() {
        simulatePaste(useControl: false)
    }

    static func simulatePaste(useControl: Bool) {
        // Requires Accessibility permission for synthetic keystrokes
        let src = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        let flags: CGEventFlags = useControl ? .maskControl : .maskCommand
        keyDown?.flags = flags
        keyUp?.flags = flags

        let loc = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }

    private static func frontmostIsTerminal() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return terminalBundleIDs.contains(bundleID)
    }
}
