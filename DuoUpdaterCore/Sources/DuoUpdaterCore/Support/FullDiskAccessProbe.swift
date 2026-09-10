#if os(macOS)
import Foundation

/// Whether Full Disk Access is in effect for this process, found by opening files
/// only it opens. macOS has no API for this — Apple DTS's advice is to do what you
/// are really trying to do and handle the error — and the read we need is the one
/// that must not be attempted without the grant, so this opens stand-ins instead.
/// The files are MacPaw PermissionsKit's list: system paths guarded by Full Disk
/// Access alone, several of them because any one may be missing, or unreadable for
/// reasons of its own.
///
/// **Why reads rather than `TCCAccessPreflight`.** Measured 2026-09-10 on macOS
/// 26.6, one process polling once a second: turned on with "Later", the reads
/// opened within the second TCC recorded the grant; turned off with "Later", they
/// were refused again within a second. Preflight kept the answer it had at launch
/// through both. So preflight alone told a user who had just granted it that it
/// was still missing, until DuoUpdater restarted.
///
/// ⚠️ **Never another app's container.** Reading one without the grant can raise
/// the "access data from other apps" prompt, or on macOS 27 a "Data Access
/// Blocked" notice — the very thing the grant check exists to avoid. A refused
/// read of these paths was silent: no prompt on macOS 26.6 (seen on screen), and
/// nothing logged for it on macOS 27. `noProbedPathIsAnotherAppsContainer` holds
/// the list to that.
public enum FullDiskAccessProbe {
    public enum Verdict: Sendable, Equatable {
        case granted, denied, inconclusive
    }

    public static var defaultPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Preferences/com.apple.TimeMachine.plist",
            "\(home)/Library/Safari/Bookmarks.plist",
            "\(home)/Library/Safari/CloudTabs.db",
        ]
    }

    /// Opens each path read-only and closes it again — the open is where TCC
    /// decides, so nothing is read. nil for an open that succeeded, else its errno.
    public static func openResults(_ paths: [String] = defaultPaths) -> [Int32?] {
        paths.map { path in
            let fd = open(path, O_RDONLY)
            let error = errno
            if fd >= 0 {
                close(fd)
                return nil
            }
            return error
        }
    }

    /// Any open that succeeded is the grant. Otherwise an `EPERM` is TCC's refusal.
    /// Anything else says nothing about it: a missing file, or `EACCES`, which is
    /// the file's own permissions — the TCC directory is reported in Apple's
    /// developer forums to be `700` on some Macs, where it fails that way with the
    /// grant too.
    public static func verdict(_ results: [Int32?]) -> Verdict {
        if results.contains(where: { $0 == nil }) { return .granted }
        if results.contains(where: { $0 == EPERM }) { return .denied }
        return .inconclusive
    }
}
#endif
