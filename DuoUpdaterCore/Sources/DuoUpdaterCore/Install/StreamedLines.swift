import Foundation

/// Reassembles a subprocess's output into lines as it streams off a pipe's
/// `readabilityHandler`, keeps the whole of it for an error message, and says
/// when the output has really ended.
///
/// A readability callback delivers whatever bytes happen to be in the pipe, not
/// lines. The runners that use this used to decode and split each chunk on its
/// own, which goes wrong two ways:
///
/// - **A line straddling two chunks came out as two fragments.** Measured
///   2026-09-13 reading `brew formulae` through that handler: 4 chunks, 2 of them
///   ending mid-line, one more "line" emitted than the bytes contained. A fragment
///   of `🍺  …/Cellar/xz/5.8.4: 96 files, 2.7MB` is not a success line, so the bulk
///   upgrade's progress count missed it.
/// - **A boundary inside a multi-byte character dropped both chunks.**
///   `String(data:encoding: .utf8)` returns nil for a chunk that ends (or starts)
///   partway through `🍺`, and the chunk was skipped outright — from the streamed
///   lines and from the collected output alike.
///
/// So bytes are buffered and split on `\n` before decoding: a newline byte never
/// occurs inside a UTF-8 multi-byte sequence, so every complete line is a whole
/// run of characters. Empty lines are skipped, as the per-chunk `split` did.
///
/// **The end of the output is EOF on the pipe, not the process exiting.** The
/// runners used to clear the handler as soon as `terminationHandler` fired, but a
/// process can exit with its last writes still sitting in the pipe buffer, and
/// those bytes were then never read. Measured 2026-09-13, `brew formulae`
/// (77,021 bytes) through the old handler, 8 runs, optimized build: 0 of 8
/// complete, each stopped at 49,659 bytes. For `brew upgrade` the lost tail is the
/// part that matters — the last `🍺` line, and the `Error:` lines
/// `BrewError.failed` reports. Hence `end()` / `waitForEnd(atMost:)`.
final class StreamedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var all = Data()
    private var pending = Data()
    private var ended = false
    private var waiter: CheckedContinuation<Void, Never>?

    /// Record one chunk and return the lines it completed, in order.
    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        all.append(chunk)
        pending.append(chunk)
        // One pass, one removal: dropping each line off the front as it is found
        // re-copies the rest of the buffer per line, which made the reader slow
        // enough to fall behind brew by tens of kilobytes.
        var lines: [String] = []
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
            if newline > start { lines.append(String(decoding: pending[start..<newline], as: UTF8.self)) }
            start = pending.index(after: newline)
        }
        pending.removeSubrange(pending.startIndex..<start)
        return lines
    }

    /// The pipe reached EOF (the readability handler read an empty chunk). Safe to
    /// call more than once.
    func end() {
        lock.lock()
        ended = true
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume()
    }

    /// Suspend until `end()`, or for at most `seconds`. The cap is for a child
    /// that outlives the process and inherits its stdout, holding the pipe open —
    /// the upgrade has finished, so its output must not be waited on forever.
    /// (brew's own background `curl` for analytics redirects to `/dev/null`, so it
    /// does not do this; the cap is for what we have not seen.)
    func waitForEnd(atMost seconds: Double) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if ended {
                lock.unlock()
                cont.resume()
                return
            }
            waiter = cont
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
                lock.lock()
                let w = waiter
                waiter = nil
                lock.unlock()
                w?.resume()
            }
        }
    }

    /// The stream has ended: return a final line that had no trailing newline, if
    /// any. Call once, after the readability handler has been cleared.
    func finish() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        let tail = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return tail
    }

    /// Everything received so far, decoded as one string.
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: all, as: UTF8.self)
    }

    /// Test seam: whether `waitForEnd` has registered and is suspended, so a test
    /// can call `end()` knowing it exercises the resume path, not the early return.
    var hasWaiter: Bool {
        lock.lock(); defer { lock.unlock() }
        return waiter != nil
    }

    /// Run `process` with stdout and stderr on one pipe, handing each line to
    /// `onOutput` as it arrives, and return everything it printed. Returns once the
    /// process has exited AND its output has reached EOF (or `eofCap` seconds
    /// after exit, whichever is first). The caller reads `terminationStatus`.
    ///
    /// The one runner for `BrewFormulaService` and `HomebrewInstaller`, which used
    /// to carry identical copies of the handler this replaces.
    static func run(
        _ process: Process,
        eofCap: Double = 5,
        onOutput: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collected = StreamedLines()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else {
                // EOF. Cleared here too: at EOF the handler is otherwise called
                // again and again with nothing to read.
                fh.readabilityHandler = nil
                collected.end()
                return
            }
            for line in collected.append(data) {
                onOutput(line)
            }
        }

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                // Installed before `run()`, so an instant exit can't beat it.
                process.terminationHandler = { _ in cont.resume() }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    cont.resume(throwing: error)
                }
            }
        } catch {
            handle.readabilityHandler = nil
            throw error
        }
        // Exiting is not the end of the output — see the type's doc comment.
        await collected.waitForEnd(atMost: eofCap)
        handle.readabilityHandler = nil
        if let tail = collected.finish() { onOutput(tail) }
        return collected.text
    }
}
