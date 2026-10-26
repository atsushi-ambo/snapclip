import Foundation
import Darwin

/// The OS releases this lock on exit, including crashes. Keep the file in place:
/// removing a locked file would let another process lock a different inode.
final class SingleInstanceLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire() throws -> SingleInstanceLock? {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first!
            .appendingPathComponent("SnapClip", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return try acquire(at: directory.appendingPathComponent(".instance.lock"))
    }

    /// A separate path allows process tests to avoid the user's running app.
    static func acquire(at url: URL) throws -> SingleInstanceLock? {
        let fd = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var keepDescriptor = false
        defer { if !keepDescriptor { close(fd) } }

        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_nlink == 1 else {
            throw POSIXError(.EPERM)
        }
        guard fchmod(fd, mode_t(0o600)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        keepDescriptor = true
        return SingleInstanceLock(descriptor: fd)
    }

    deinit { close(descriptor) }
}
