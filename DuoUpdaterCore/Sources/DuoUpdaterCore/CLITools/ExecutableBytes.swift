import Foundation

/// Searches an executable's bytes for a literal **without mapping the file**.
///
/// The scanners that read a version out of a binary (`BoatScanner`, `BunScanner`,
/// `OpencodeScanner`) first mapped the file (`Data(contentsOf:options:
/// .alwaysMapped)`) and searched it. That is safe only while the file's code
/// signature is valid. OpenCode's ad hoc builds before 1.18.34 have a signature
/// that no longer validates (`codesign --verify`: "code or signature have been
/// modified", 1.18.15 and 1.18.33, 2026-10-04), and once the kernel has that
/// signature on record for the file — after a `SecStaticCode` check of it, as the
/// trust rule makes — a process running under the hardened runtime that maps the
/// file and faults in a page that fails its hash is killed: `SIGKILL (Code
/// Signature Invalid)` inside `Data.range(of:)`, measured in the hardened test
/// runner the same day, while an unhardened process mapping the same file was
/// not. The shipped app runs hardened, so a mapped search of such a file would
/// end DuoUpdater, not just the check.
///
/// `read(2)` copies bytes and validates nothing, so the file is read in chunks
/// instead, each kept with enough of the previous one that a literal spanning a
/// boundary is still found whole.
enum ExecutableBytes {

    /// The window around each occurrence of `marker`: `before` bytes ahead of it
    /// (or as many as the file has), the marker, and `after` bytes past it (or as
    /// many as are left), in file order. nil when the file cannot be read.
    /// Blocking.
    static func windows(
        in url: URL, marker: Data, before: Int, after: Int, chunkSize: Int = 4 << 20
    ) -> [Data]? {
        guard !marker.isEmpty, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var buffer = Data()
        var windows: [Data] = []
        // Offset into `buffer` where the next occurrence may start: everything
        // before it has been searched (and any occurrence there reported).
        var searchFrom = 0
        var reachedEnd = false
        while !reachedEnd {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: chunkSize) ?? Data()
            } catch {
                return nil
            }
            reachedEnd = chunk.isEmpty
            buffer.append(chunk)
            while true {
                let from = buffer.startIndex + searchFrom
                guard from < buffer.endIndex, let range = buffer.range(of: marker, in: from..<buffer.endIndex) else {
                    // No occurrence starts before the last `marker.count - 1`
                    // bytes, which may yet begin one.
                    searchFrom = max(searchFrom, buffer.count - (marker.count - 1))
                    break
                }
                // Not enough after it yet: wait for the next chunk, unless there is none.
                guard reachedEnd || buffer.endIndex - range.upperBound >= after else {
                    searchFrom = range.lowerBound - buffer.startIndex
                    break
                }
                let lower = max(buffer.startIndex, range.lowerBound - before)
                let upper = min(buffer.endIndex, range.upperBound + after)
                windows.append(Data(buffer[lower..<upper]))
                searchFrom = range.upperBound - buffer.startIndex
            }
            // Keep only what an occurrence not yet reported can need: `before`
            // bytes ahead of where the next search starts.
            let dropped = max(0, searchFrom - before)
            if dropped > 0 {
                buffer = Data(buffer.suffix(buffer.count - dropped))
                searchFrom -= dropped
            }
        }
        return windows
    }

    /// The windows joined by a zero byte — which no version literal contains —
    /// so a scanner's `compiledVersion(in:)` reads every occurrence, and only
    /// those, as it read the whole file before.
    static func joinedWindows(in url: URL, marker: Data, before: Int, after: Int) -> Data? {
        guard let windows = windows(in: url, marker: marker, before: before, after: after) else { return nil }
        return Data(windows.joined(separator: [0]))
    }

    /// The file's first `count` bytes — a Mach-O header — read, not mapped.
    static func head(of url: URL, count: Int = 8) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }
}
