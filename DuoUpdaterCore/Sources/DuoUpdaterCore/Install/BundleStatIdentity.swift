import CryptoKit
import Darwin
import Foundation

/// A digest of what the filesystem says about every entry in a bundle — names,
/// types, sizes, file ids and timestamps — read with `lstat` alone, never a
/// byte of content.
///
/// It exists so a retried install can tell that the bundle it is about to back
/// up is the very one the store already holds a copy of, without paying for
/// the copy and the content hash a second time. ``BackupManifest`` answers
/// "are these the bytes we stored"; this answers the cheaper question "has
/// anything been written to this tree since we last looked", and only a
/// matching answer on the *source* — recorded just before the copy that the
/// manifest was then computed from — lets a later attempt reuse that copy.
///
/// **Why a match cannot mean different bytes.** Every write to a regular file
/// through the filesystem moves its change time (`st_ctime`), and that field
/// is the one userland cannot set: `setattrlist(2)` says "ATTR_CMN_CHGTIME
/// cannot be set programmatically. Any attempt to set change time is
/// ignored", and `utimes`/`futimens` set only access and modification time,
/// moving the change time to the moment of the call. Measured 2026-10-19 on
/// APFS: a same-size rewrite with `utimes` putting the old mtime back kept
/// size and inode and moved ctime; `setattrlist` of the old ctime returned 0
/// and changed nothing. That is why ctime, not mtime, carries this. A file that
/// is replaced rather than rewritten (rename over it, a new clone) arrives as a
/// different file id. An entry that is added, removed or renamed changes the
/// set of paths, and a symlink is recorded by its target, which is what the
/// manifest hashes it by. Whatever a later attempt reads, then, it can only
/// equal this digest if no entry was written, replaced, added or removed.
///
/// One gap is closed by refusing to answer: a file written so soon before the
/// walk that a second write could land on the *same* timestamp reading (on
/// APFS that is the same nanosecond; HFS+ keeps whole seconds). Any entry whose
/// modification or change time is within ``racyWindow`` of the walk makes this
/// return nil — "cannot vouch" — the way git treats a racily-clean index entry.
///
/// What it cannot see, and does not claim to: changes made beneath the
/// filesystem (a raw write to the device, media corruption), and a write that
/// lands after the wall clock was set back to exactly the earlier change time.
/// Neither is a change anything on this Mac makes to an app on purpose. A
/// reused copy is still checked against its manifest on restore, as every
/// backup is.
///
/// Directory timestamps are deliberately left out. A directory's own change
/// time moves on things that are not its contents — the bundle directory
/// carries extended attributes the system writes (`com.apple.macl`, Spotlight's
/// `_kMDItemLastOutOfSpotlightEngagementDate` on `/Applications/ChatGPT.app`,
/// seen 2026-10-19), and the manifest hashes no directory metadata at all —
/// while its entries are all enumerated anyway. Leaving it in would only stop
/// a retry from matching for reasons that change no stored byte.
public enum BundleStatIdentity {

    /// How close to the walk an entry's timestamps may be before the walk
    /// cannot vouch for it. Two seconds covers HFS+'s one-second timestamps
    /// with room to spare; APFS needs only a nanosecond.
    public static let racyWindow: TimeInterval = 2

    /// Test seam: a window to use instead of ``racyWindow``, so a fixture
    /// written a moment ago can be vouched for without the test sleeping. Bound
    /// per task, like `BackupStore`'s seams; production never binds it. A
    /// Dispatch thread does not see it, so a caller that walks off the
    /// cooperative pool reads ``currentRacyWindow`` first and passes it in.
    @TaskLocal public static var racyWindowOverride: TimeInterval?

    /// The window in force on the calling task.
    public static var currentRacyWindow: TimeInterval { racyWindowOverride ?? racyWindow }

    /// The digest for the tree at `bundle`, or nil when it cannot be
    /// vouched for: the bundle cannot be walked, an entry cannot be
    /// `lstat`ed, or an entry was written within `window` of `now`.
    ///
    /// `now` is read before the walk starts, so a write during the walk is
    /// either seen by it or later than `now` — both of which keep a later
    /// match from being false.
    public static func compute(
        for bundle: URL, now: Date = Date(), racyWindow window: TimeInterval = currentRacyWindow
    ) -> String? {
        let base = bundle.standardizedFileURL.path
        var root = stat()
        guard lstat(base, &root) == 0, (root.st_mode & S_IFMT) == S_IFDIR else { return nil }
        guard let walker = FileManager.default.enumerator(atPath: base) else { return nil }
        let cutoff = now.timeIntervalSince1970 - window
        var lines: [String] = []
        while let relative = walker.nextObject() as? String {
            let full = base + "/" + relative
            var st = stat()
            guard lstat(full, &st) == 0 else { return nil }
            switch st.st_mode & S_IFMT {
            case S_IFDIR:
                lines.append("\(relative)\0d")
            case S_IFLNK:
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: full)
                else { return nil }
                lines.append("\(relative)\0l\0\(target)")
            case S_IFREG:
                let m = st.st_mtimespec, c = st.st_ctimespec
                if seconds(m) >= cutoff || seconds(c) >= cutoff { return nil }
                lines.append(
                    "\(relative)\0f\0\(st.st_size)\0\(st.st_dev)\0\(st.st_ino)"
                    + "\0\(m.tv_sec).\(m.tv_nsec)\0\(c.tv_sec).\(c.tv_nsec)")
            default:
                // Sockets, fifos: no content to hash, but a change in what is
                // there is still a change.
                lines.append("\(relative)\0o\0\(st.st_mode)\0\(st.st_ino)")
            }
        }
        lines.sort()
        var hasher = SHA256()
        // NUL-separated: the one byte a path cannot contain, so no two trees
        // render to the same stream.
        for line in lines { hasher.update(data: Data((line + "\0\0").utf8)) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func seconds(_ t: timespec) -> TimeInterval {
        TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1_000_000_000
    }
}
