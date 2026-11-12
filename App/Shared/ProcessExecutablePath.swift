import Darwin
import Foundation

/// Read-only process identity shared by the app and its privileged helper.
/// The start timestamp is checked on both sides of XPC: a recycled PID must
/// never turn an unknown process into an unrelated executable.
enum ProcessExecutablePath {
    struct Identity: Equatable, Sendable {
        let seconds: Int64
        let microseconds: Int32
    }

    static func identity(of pid: Int32) -> Identity? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0,
              size == MemoryLayout<kinfo_proc>.size, info.kp_proc.p_pid == pid,
              info.kp_proc.p_stat != SZOMB else { return nil }
        return Identity(seconds: Int64(info.kp_proc.p_starttime.tv_sec),
                        microseconds: info.kp_proc.p_starttime.tv_usec)
    }

    static func read(pid: Int32, expected: Identity,
                     identity: (Int32) -> Identity? = identity,
                     executablePath: (Int32) -> String? = executablePath) -> String? {
        guard pid > 0, expected.seconds > 0,
              (0..<1_000_000).contains(expected.microseconds),
              identity(pid) == expected,
              let path = executablePath(pid), path.hasPrefix("/"), !path.contains("\0"),
              identity(pid) == expected else { return nil }
        return path
    }

    private static func executablePath(of pid: Int32) -> String? {
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = Int(proc_pidpath(pid, &path, UInt32(path.count)))
        if length > 0 {
            return String(bytes: path.prefix(length).map { UInt8(bitPattern: $0) }, encoding: .utf8)
        }
        // An unlinked executable has no vnode path. Read only the saved exec
        // path at the start of KERN_PROCARGS2, never argv[0] or the environment.
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size, size <= 1_048_576 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0,
              size <= bytes.count, size > MemoryLayout<Int32>.size else { return nil }
        let saved = bytes[MemoryLayout<Int32>.size..<size]
        guard let end = saved.firstIndex(of: 0) else { return nil }
        return String(bytes: saved[..<end], encoding: .utf8)
    }
}
