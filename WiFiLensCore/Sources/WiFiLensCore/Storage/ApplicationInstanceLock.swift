import Darwin
import Foundation

/// Holds an exclusive process lock until the owner is released or the process exits.
public final class ApplicationInstanceLock {
    private let descriptor: Int32

    /// Returns nil when another process holds the lock; other failures are reported to the caller.
    public init?(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }
}
