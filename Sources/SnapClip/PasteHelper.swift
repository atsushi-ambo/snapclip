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

    /// The menu action already restored the clip; never overwrite a newer copy.
    static func pasteRestoredClip(kind: ClipKind, changeCount: Int, target: NSRunningApplication?) {
        NSLog("SnapClip: paste requested; accessibility=%@; eventAccess=%@; destination=%@",
              AXIsProcessTrusted() ? "yes" : "no",
              CGPreflightPostEventAccess() ? "yes" : "no", target?.bundleIdentifier ?? "none")
        guard AXIsProcessTrusted() else {
            showAccessibilityHelp(copied: true)
            return
        }
        guard let target, !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            showFailure("The clip is copied. Select a destination app and press ⌘V to paste.")
            return
        }

        let useControl = kind == .image &&
            terminalBundleIDs.contains(target.bundleIdentifier ?? "")
        target.activate(options: [])
        sendWhenReady(target: target, useControl: useControl, changeCount: changeCount, attemptsRemaining: 40)
    }

    private static func sendWhenReady(target: NSRunningApplication, useControl: Bool,
                                      changeCount: Int, attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard NSPasteboard.general.changeCount == changeCount else {
                NSLog("SnapClip: cancelled pending paste because clipboard changed")
                return
            }
            // Do not send while the picker shortcut's modifiers are still held.
            let held = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
            guard target.isActive, held.isEmpty else {
                if attemptsRemaining > 0 && !target.isTerminated {
                    sendWhenReady(target: target, useControl: useControl,
                                  changeCount: changeCount, attemptsRemaining: attemptsRemaining - 1)
                } else {
                    showFailure("The destination did not become ready. The clip is copied; press ⌘V to paste it.")
                }
                return
            }
            simulatePaste(useControl: useControl, target: target)
        }
    }

    private static func simulatePaste(useControl: Bool, target: NSRunningApplication) {
        // Isolate synthetic events from the shortcut that opened the picker.
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            showFailure("Could not send the paste shortcut. The clip is copied; press ⌘V to paste it.")
            return
        }
        let flags: CGEventFlags = useControl ? .maskControl : .maskCommand
        down.flags = flags
        up.flags = flags
        // Address the captured destination rather than routing back through the
        // global hotkey/menu event tap. Keep down/up ordered in that process.
        down.postToPid(target.processIdentifier)
        up.postToPid(target.processIdentifier)
        NSLog("SnapClip: sent %@V to %@", useControl ? "Ctrl+" : "Cmd+",
              target.bundleIdentifier ?? "unknown")
    }

    static func showAccessibilityHelp(copied: Bool = false) {
        let alert = NSAlert()
        alert.messageText = copied ? "Clip copied — allow automatic paste" : "Allow SnapClip to paste"
        alert.informativeText = """
        Open System Settings → Privacy & Security → Accessibility and enable SnapClip.

        If SnapClip is already enabled but pasting stopped after an update, remove its old entry with −, then add ~/Applications/SnapClip.app again with + and enable it.

        \(copied ? "Your selected clip is on the clipboard. Return to your app and press ⌘V to paste it now." : "This permission lets SnapClip send the paste shortcut to your app.")
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func showFailure(_ message: String) {
        NSLog("SnapClip: %@", message)
        let alert = NSAlert()
        alert.messageText = "Could not paste automatically"
        alert.informativeText = message
        alert.runModal()
    }
}
