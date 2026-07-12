import AppKit
import Carbon

/// Global hotkey via Carbon (⌘⇧V by default).
final class HotkeyManager {
    static var shared: HotkeyManager?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onHotkey: (() -> Void)?

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_V), modifiers: UInt32 = UInt32(cmdKey | shiftKey)) {
        unregister()
        HotkeyManager.shared = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let statusHandler = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let event else { return noErr }
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if hkID.id == 1 {
                    DispatchQueue.main.async {
                        HotkeyManager.shared?.onHotkey?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )

        if statusHandler != noErr {
            NSLog("SnapClip: InstallEventHandler failed (\(statusHandler))")
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x534E4350), id: 1) // 'SNCP'
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("SnapClip: hotkey register failed (\(status)). ⌘⇧V may be taken (e.g. by Clipy).")
        } else {
            NSLog("SnapClip: hotkey registered — ⌘⇧V")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        unregister()
        if HotkeyManager.shared === self {
            HotkeyManager.shared = nil
        }
    }
}
