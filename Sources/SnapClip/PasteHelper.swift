import AppKit
import Carbon.HIToolbox

enum PasteHelper {
    /// Set pasteboard from history item and simulate Cmd+V into the frontmost app.
    static func paste(item: ClipItem, store: HistoryStore) {
        store.markIgnoreNextChange()
        guard store.restoreToPasteboard(item) else {
            NSLog("SnapClip: failed to restore item to pasteboard")
            return
        }

        // Give the pasteboard a moment, then send Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulateCommandV()
        }
    }

    static func simulateCommandV() {
        // Requires Accessibility permission for synthetic keystrokes
        let src = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        let loc = CGEventTapLocation.cghidEventTap
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }
}
