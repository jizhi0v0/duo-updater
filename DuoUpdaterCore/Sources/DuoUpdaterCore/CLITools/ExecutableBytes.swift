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
/// boundary is still found whole. The same holds for every other reader of
/// executables that are not ours: `BundleFactsReader` (each Mach-O in a bundle),
/// `BlenderBuildInfo` and `FeedDiscovery` (each Mach-O and `app.asar` in a
/// bundle) read through ``forEachChunk(of:overlap:chunkSize:_:)``.
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

    /// Hands `body` the whole file, read rather than mapped, a chunk at a time,
    /// each chunk preceded by the last `overlap` bytes of the buffer before it
    /// (fewer at the start of the file): `body(buffer, carried, isLast)`, where
    /// `buffer`'s first `carried` bytes are that overlap and `isLast` says nothing
    /// follows `buffer` in the file — a last call may bring no new bytes at all.
    /// A scanner that needs context on either side of what it matches judges a
    /// position only once that context is in the buffer, and the overlap carries
    /// the rest to the next call. `body` returns false to stop reading. Returns
    /// false when the file cannot be read; `buffer` is valid only during the call.
    /// Blocking.
    ///
    /// Reading costs no more than mapping did. Measured 2026-10-06 on this Mac's
    /// `/Applications` (release build): over all 8,758 Mach-O files (44.7 GB),
    /// each warm in the page cache as `BundleFactsReader`'s hash leaves it and
    /// scanned both ways in alternating order, source paths plus the strings
    /// index took 63.11 s mapped and 63.32 s read in 4 MB chunks, with identical
    /// results; whole `BundleFactsReader.scan` runs over the 128 apps took 334 s
    /// before and 325 s after.
    static func forEachChunk(
        of url: URL, overlap: Int, chunkSize: Int = 4 << 20,
        _ body: (_ buffer: UnsafeRawBufferPointer, _ carried: Int, _ isLast: Bool) -> Bool
    ) -> Bool {
        precondition(overlap >= 0 && chunkSize > 0)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: overlap + chunkSize, alignment: 16)
        defer { buffer.deallocate() }
        let base = buffer.baseAddress!
        var carried = 0
        while true {
            var filled = 0
            while filled < chunkSize {
                let n = read(handle.fileDescriptor, base + carried + filled, chunkSize - filled)
                if n > 0 {
                    filled += n
                } else if n == 0 {
                    break
                } else if errno != EINTR {
                    return false
                }
            }
            let count = carried + filled
            let isLast = filled < chunkSize
            guard body(UnsafeRawBufferPointer(start: base, count: count), carried, isLast), !isLast else {
                return true
            }
            let kept = min(overlap, count)
            memmove(base, base + count - kept, kept)
            carried = kept
        }
    }

    /// Every occurrence of a marker in a file read with
    /// ``forEachChunk(of:overlap:chunkSize:_:)``, in file order, overlapping ones
    /// included, each reported once and with at least `before` bytes ahead of it in
    /// the buffer it is reported in (fewer only at the start of the file).
    struct MarkerSearch {
        let marker: [UInt8]
        let before: Int
        /// Trailing bytes of the last buffer where an occurrence may yet start.
        private var undecided = 0

        init(marker: Data, before: Int) {
            precondition(!marker.isEmpty)
            self.marker = Array(marker)
            self.before = before
        }

        /// What `forEachChunk` must carry over for this.
        var overlap: Int { before + marker.count - 1 }

        /// Calls `found` with the offset in `bytes` of each occurrence not reported
        /// before, until it returns false.
        mutating func feed(_ bytes: UnsafeRawBufferPointer, carried: Int, _ found: (Int) -> Bool) {
            var from = carried - undecided
            // Where no whole occurrence fits yet.
            undecided = min(bytes.count - from, marker.count - 1)
            guard let base = bytes.baseAddress else { return }
            marker.withUnsafeBytes { needle in
                while from + needle.count <= bytes.count,
                      let hit = memmem(base + from, bytes.count - from, needle.baseAddress!, needle.count) {
                    let at = base.distance(to: UnsafeRawPointer(hit))
                    guard found(at) else { return }
                    from = at + 1
                }
            }
        }
    }

    /// The file's first `count` bytes — a Mach-O header — read, not mapped.
    static func head(of url: URL, count: Int = 8) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }
}
