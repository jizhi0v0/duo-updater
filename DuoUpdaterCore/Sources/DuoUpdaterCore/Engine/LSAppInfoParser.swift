import Foundation

/// Parses the text `lsappinfo list` prints, into the one thing
/// `computeRestartInfo` needs from it: resolved bundle path → the
/// `CFBundleVersion` the running process actually launched with.
///
/// Pure and file-I/O-free on purpose — the app is the one thing that knows how
/// to invoke `/usr/bin/lsappinfo` (with its timeout/kill backstop for a wedged
/// process); everything about what the text MEANS belongs here, where it can be
/// asserted against fixed strings instead of a live process list.
public enum LSAppInfoParser {

    /// What LaunchServices stamps on a record whose app already exited but whose
    /// process coalition still has a member alive.
    static let tombstoneMarker = "(exited-with-subordinates)"

    /// Build the path → version map, discarding any record LaunchServices marks
    /// `(exited-with-subordinates)`.
    ///
    /// That marker is a tombstone: the app's own process already exited, but
    /// LaunchServices keeps the record around because something it spawned (a
    /// helper, a bundled daemon) — or another member of its process coalition —
    /// is still alive. The `Version` on that record is frozen at whatever build
    /// launched, which after an update is the OLD one, so treating the record as
    /// "running" makes `disk newer than running` true forever and the Relaunch
    /// badge never clears (issue #473).
    ///
    /// Measured 2026-09-09 on macOS 27.0.0 (arm64), three real records:
    ///   - a UIElement helper whose main process had quit, one coalition member
    ///     still alive: `pid = 1193 … Version=[ NULL ] … Arch=ARM64
    ///     (exited-with-subordinates)`. `Version` unquoted, so `quotedValue`
    ///     already skipped it regardless of this guard.
    ///   - the reporter's own case (AndroMeld, a sandboxed app):
    ///     `pid = 32196 … Version="2608.29.0" … sandboxed (exited-with-subordinates)`
    ///     — here `Version` IS quoted, so without this guard it reads as the live
    ///     running build. This is the shape the bug turned on.
    ///   - one live tombstone in a full `lsappinfo list` sweep (1092 lines, 106
    ///     records), also with an unquoted `Version`.
    /// `strings` on `/usr/bin/lsappinfo` shows `(exited-with-subordinates)` is the
    /// only literal parenthetical status marker the `list` format emits — the six
    /// other `exited`-bearing literals in that binary are API key names and flag
    /// spellings, none of them parenthesised. Scanning that same 1092-line sweep for
    /// parenthesised tokens turned up only app names plus `(PID …)`, `(Renderer)`
    /// and `(in front)` beside it.
    ///
    /// **Why the whole record is discarded rather than just the marked line.** In all
    /// three observations the marker sat on the same `pid = …` line as `Version`, so
    /// skipping that one line would have sufficed — but three samples are not a format
    /// guarantee, and the failure mode of being wrong is silent: a tombstone whose
    /// `Version` landed on some other line would be read as a live build again, which
    /// is precisely bug #473 returning with no test to catch it.
    ///
    /// Getting that independence requires **holding the version back** rather than
    /// clearing a cursor: a record is only committed once the next record begins (or
    /// the text ends), so a marker appearing anywhere inside it — before the `Version`
    /// line, on it, or after it — still cancels the whole thing. Simply nulling the
    /// current path on the marker line would leave a marker that trails `Version` too
    /// late to matter, which is the half of the format we have the least evidence about.
    ///
    /// The pre-existing first-wins rule survives as two guards: `held == nil` keeps the
    /// FIRST `Version` line within a record, and `map[path] == nil` at commit time keeps
    /// the first record for a path — so a live record already recorded is never
    /// overwritten by a later tombstone for the same path.
    public static func runningBuildVersions(from text: String) -> [String: String] {
        var map: [String: String] = [:]
        var current: String?
        /// The version read for `current`, not yet committed: a tombstone marker later
        /// in the same record still has to be able to cancel it.
        var held: String?

        func commitCurrentRecord() {
            guard let path = current, let version = held else { return }
            if map[path] == nil { map[path] = version }
        }

        for line in text.split(separator: "\n") {
            if let path = quotedValue(after: "bundle path", in: line) {
                commitCurrentRecord()
                // Resolve symlinks to line up with how `AppScanner` records
                // `InstalledApp.path` (and `computeRestartInfo`'s lookup key).
                current = UpdatePolicy.runtimeBundlePath(URL(fileURLWithPath: path))
                held = nil
            } else if line.contains(tombstoneMarker) {
                current = nil
                held = nil
            } else if current != nil, held == nil,
                      let version = quotedValue(after: "Version", in: line) {
                held = version
            }
        }
        commitCurrentRecord()
        return map
    }

    /// Extract the value of a `key="value"` pair from a line.
    ///
    /// ⚠️ Substring search, so `key` matches as a suffix too: asking for `Version`
    /// would also accept a `SomethingVersion="…"` pair. No `lsappinfo list` output
    /// measured so far carries one, and this behaviour predates #473 — noted rather
    /// than changed, so a future reader does not mistake it for intent.
    static func quotedValue(after key: String, in line: Substring) -> String? {
        guard let start = line.range(of: key + "=\"") else { return nil }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}
