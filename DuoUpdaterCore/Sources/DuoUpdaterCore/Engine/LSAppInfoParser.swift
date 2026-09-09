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
    /// Build the path → version map, skipping any entry LaunchServices marks
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
    /// Measured 2026-09-09 on macOS 27.0.0 (arm64), two real records:
    ///   - a UIElement helper whose main process had quit, one coalition member
    ///     still alive: `pid = 1193 … Version=[ NULL ] … Arch=ARM64
    ///     (exited-with-subordinates)` — the marker trails every other flag on
    ///     the `pid = …` line, after a sandboxed-or-not app with `Version=[ NULL ]`
    ///     (unquoted, so `quotedValue` already skips it regardless of this guard).
    ///   - the reporter's own case (AndroMeld, a sandboxed app):
    ///     `pid = 32196 … Version="2608.29.0" … sandboxed (exited-with-subordinates)`
    ///     — here `Version` IS quoted, so without this guard it would be read as
    ///     the live running build.
    /// `strings` on `/usr/bin/lsappinfo` shows `(exited-with-subordinates)` is
    /// the only literal parenthetical status marker the tool's `list` format
    /// emits — there is no separate bare `(exited)` to also guard against, and
    /// nothing else in that binary looks like a second spelling of it.
    ///
    /// The marker always trails the same `pid = …` line the (quoted-or-not)
    /// `Version` appears on, alongside `sandboxed`/`!signalled`/etc — so this
    /// checks the current line only, not a flag carried across lines.
    public static func runningBuildVersions(from text: String) -> [String: String] {
        var map: [String: String] = [:]
        var current: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let path = quotedValue(after: "bundle path", in: line) {
                current = UpdatePolicy.runtimeBundlePath(URL(fileURLWithPath: path))
            } else if let cur = current, map[cur] == nil,
                      !line.contains("(exited-with-subordinates)"),
                      let version = quotedValue(after: "Version", in: line) {
                map[cur] = version
            }
        }
        return map
    }

    /// Extract the value of a `key="value"` pair from a line.
    static func quotedValue(after key: String, in line: Substring) -> String? {
        guard let start = line.range(of: key + "=\"") else { return nil }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}
