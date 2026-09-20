import Foundation

/// One running instance per data directory, like Electron's
/// requestSingleInstanceLock() (which is per-userData). An flock(2) on a file in
/// the data directory: the kernel drops it when the process dies, so a crash can
/// never leave a stale lock behind. Demo mode uses its own data directory, so a
/// demo instance runs alongside the real one.
public final class InstanceLock {
    private let fd: Int32

    /// nil if another process (or another InstanceLock in this one) holds the lock.
    public init?(path: URL) {
        let fd = open(path.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        self.fd = fd
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
