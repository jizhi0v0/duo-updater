import Foundation

/// Which Lapce build a copy is — the stable release or the nightly — read out of
/// its executable.
///
/// **Why the executable.** Lapce's nightly (the `nightly` prerelease, rebuilt
/// every day) ships the stable release's bundle id `io.lapce`, its Team, its
/// asset name `Lapce-macos.dmg`, and a byte-identical Info.plist: the plist is a
/// checked-in template whose `CFBundleShortVersionString` moves only in the
/// `release: vX.Y.Z` commit, so every nightly after 0.4.6 says `0.4.6` until the
/// next release (both 2026-10-09 nightly and v0.4.6 read, `diff` empty). The
/// difference is compiled in: `lapce-core/build.rs` writes
/// `NAME = "Lapce-<Stable|Nightly|Debug>"` from `RELEASE_TAG_NAME` (a `v` tag is
/// Stable, anything else a release-profile build calls Nightly), and the app
/// keeps its settings, plugins and the updater's own track under that name
/// (`ProjectDirs::from("dev", "lapce", NAME)`; the nightly's updater asks
/// `releases/tags/nightly`, the stable one `releases/latest`).
///
/// Measured on the real binaries (universal, both slices carry the constant):
/// the 2026-10-09 nightly holds `Lapce-Nightly` twice and `Lapce-Stable` never;
/// v0.4.6 and v0.4.5 hold `Lapce-Stable` three times and `Lapce-Nightly` never.
/// `+Nightly.` alone is NOT a marker: it is in every stable build too, as the
/// format string the updater builds a nightly's version with.
///
/// Why it matters: with only the stable GitHub rule, a nightly copy reads as
/// stable, and the next stable release would be offered and installed over it —
/// a different track, and one that reads its settings from another directory.
/// Calling it `.nightly` makes the stable rule step aside (`GitHubReleasesSource`'s
/// channel gate).
public enum LapceBuild {
    public static let bundleID = "io.lapce"

    private static let nightlyMarker = Data("Lapce-Nightly".utf8)

    /// `.nightly` when the executable carries the nightly's name constant, nil
    /// otherwise (stable, or nothing readable): nil leaves the ordinary channel
    /// detection standing. Remembered per executable identity (size and mtime),
    /// since a stable copy's read walks the whole executable (94 MB at 0.4.6);
    /// a nightly's stops at the first hit (byte 35,277,466 of 90,539,952 in the
    /// 2026-10-09 nightly).
    public static func channel(bundleAt bundleURL: URL) -> ReleaseChannel? {
        let plist = NSDictionary(
            contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard let executable = AppRuntimeDetector.executableURL(
            bundleAt: bundleURL, infoPlist: plist ?? [:], fm: FileManager.default)
        else { return nil }
        let key = RuntimeVersion.executableIdentity(of: executable).map { "\(executable.path)|\($0)" }
        if let key, let remembered = cached(key) { return remembered.channel }
        guard let isNightly = isNightly(contentsOf: executable) else { return nil }
        let channel: ReleaseChannel? = isNightly ? .nightly : nil
        if let key { remember(Remembered(channel: channel), for: key) }
        return channel
    }

    /// Whether the file holds the nightly marker, read a chunk at a time and
    /// never mapped (`ExecutableBytes`). Nil when the file cannot be read.
    static func isNightly(contentsOf url: URL, chunkSize: Int = 4 << 20) -> Bool? {
        var search = ExecutableBytes.MarkerSearch(marker: nightlyMarker, before: 0)
        var found = false
        let readable = ExecutableBytes.forEachChunk(
            of: url, overlap: search.overlap, chunkSize: chunkSize
        ) { bytes, carried, _ in
            search.feed(bytes, carried: carried) { _ in
                found = true
                return false
            }
            return !found
        }
        return readable ? found : nil
    }

    private struct Remembered { let channel: ReleaseChannel? }
    private nonisolated(unsafe) static var cache: [String: Remembered] = [:]
    private static let cacheLock = NSLock()

    private static func cached(_ key: String) -> Remembered? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }

    private static func remember(_ value: Remembered, for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache[key] = value
    }
}
