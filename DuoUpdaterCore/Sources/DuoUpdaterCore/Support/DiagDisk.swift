import Foundation

/// DIAG branch only: an append-only log of every hdiutil/diskutil call.
public enum DiagDisk {
    static let path = ProcessInfo.processInfo.environment["DUO_DIAG_DISK_LOG"]

    static func watched(_ executable: String) -> Bool {
        path != nil && (executable.hasSuffix("/hdiutil") || executable.hasSuffix("/diskutil"))
    }

    public static func stamp() -> String {
        var tv = timeval()
        gettimeofday(&tv, nil)
        var t = tm()
        var secs = tv.tv_sec
        localtime_r(&secs, &t)
        return String(format: "%02d:%02d:%02d.%03d", t.tm_hour, t.tm_min, t.tm_sec, Int(tv.tv_usec / 1000))
    }

    public static func flat(_ data: Data) -> String {
        flat(String(decoding: data, as: UTF8.self))
    }

    public static func flat(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\t", with: " ")
    }

    private static let lock = NSLock()

    public static func line(_ s: String) {
        guard let path else { return }
        lock.withLock {
            let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            guard fd >= 0 else { return }
            let bytes = Array((s + "\n").utf8)
            _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
        }
    }
}
