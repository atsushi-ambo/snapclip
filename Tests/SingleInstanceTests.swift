import Foundation
import Darwin

// Helper processes use only synthetic lock files, never clipboard or app data.
if CommandLine.arguments.count == 3 {
    let mode = CommandLine.arguments[1]
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    if mode == "--probe" || mode == "--hold" {
        guard let lock = try SingleInstanceLock.acquire(at: url) else { exit(10) }
        withExtendedLifetime(lock) {
            if mode == "--hold" {
                FileHandle.standardOutput.write(Data("ready\n".utf8))
                _ = FileHandle.standardInput.readDataToEndOfFile()
            }
        }
        exit(0)
    }
}

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("SnapClipLockTests-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let lockURL = directory.appendingPathComponent("instance.lock")

func probe() throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["--probe", lockURL.path]
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

var first = try SingleInstanceLock.acquire(at: lockURL)
precondition(first != nil)
let duplicate = try SingleInstanceLock.acquire(at: lockURL)
precondition(duplicate == nil, "Reject duplicate in same process")
let blocked = try probe()
precondition(blocked == 10, "Reject duplicate in a different process")
first = nil
let restarted = try probe()
precondition(restarted == 0, "Allow restart after owner exits")

let holder = Process()
let input = Pipe()
let output = Pipe()
holder.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
holder.arguments = ["--hold", lockURL.path]
holder.standardInput = input
holder.standardOutput = output
try holder.run()
defer {
    try? input.fileHandleForWriting.close()
    if holder.isRunning { holder.terminate() }
    holder.waitUntilExit()
}
let ready = output.fileHandleForReading.readData(ofLength: 6)
precondition(ready == Data("ready\n".utf8))
let blockedByHolder = try probe()
precondition(blockedByHolder == 10, "An existing owner must keep its lock")
holder.terminate()
holder.waitUntilExit()
let recovered = try probe()
precondition(recovered == 0, "Recover automatically after a crash or forced exit")

let target = directory.appendingPathComponent("do-not-touch")
try Data("unchanged".utf8).write(to: target)
let symlink = directory.appendingPathComponent("symlink.lock")
try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
do {
    _ = try SingleInstanceLock.acquire(at: symlink)
    preconditionFailure("Refuse a symlink lock file")
} catch { }
let preserved = try String(contentsOf: target, encoding: .utf8)
precondition(preserved == "unchanged")
do {
    _ = try SingleInstanceLock.acquire(at: directory)
    preconditionFailure("Refuse a directory lock")
} catch { }
print("PASS: single instance across processes; restart and crash recovery; unsafe lock paths refused")
