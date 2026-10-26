import AppKit

// LaunchAgents and Login Items can start the executable simultaneously. Acquire
// one atomic lock before opening history files, registering hotkeys or adding UI.
let instanceLock: SingleInstanceLock
do {
    guard let acquired = try SingleInstanceLock.acquire() else {
        NSLog("SnapClip: another instance is already running; exiting")
        exit(EXIT_SUCCESS)
    }
    instanceLock = acquired
} catch {
    NSLog("SnapClip: cannot acquire instance lock: %@", error.localizedDescription)
    exit(EXIT_FAILURE)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
withExtendedLifetime(instanceLock) {
    app.run()
}
