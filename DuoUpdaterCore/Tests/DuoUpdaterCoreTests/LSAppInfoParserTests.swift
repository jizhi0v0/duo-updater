import Foundation
import Testing
@testable import DuoUpdaterCore

/// `LSAppInfoParser.runningBuildVersions` turns `lsappinfo list`'s text into
/// path → running-build-version. Its one job beyond the original path/Version
/// scrape is excluding `(exited-with-subordinates)` tombstones — records
/// LaunchServices keeps for an app whose own process already quit because
/// something it spawned (or another coalition member) is still alive. Reading
/// one of those as "running" is issue #473: the frozen pre-update `Version` on
/// the tombstone reads as older than the disk build forever, so Relaunch never
/// clears even after the app is long gone and the update long applied.
///
/// Every fixture below is built from the two real `lsappinfo list` records
/// measured 2026-09-09 on macOS 27.0.0 (arm64) — not retyped from the issue's
/// single sample, since that text is one observation, not a spec. Both are
/// reproduced verbatim except for cosmetic renaming (the running app's own
/// name/bundle id/pid), confirmed byte-for-byte against `lsappinfo list`
/// output captured on this machine:
///   - a sandboxed app, `Version` QUOTED, marker trailing `sandboxed`:
///     `pid = 32196 … Version="2608.29.0" … sandboxed (exited-with-subordinates)`
///     (this is also the shape the issue itself reports for AndroMeld).
///   - a non-sandboxed UIElement helper, `Version` UNQUOTED (`[ NULL ]`),
///     marker trailing `Arch=ARM64` directly (no `sandboxed`):
///     `pid = 1193 … Version=[ NULL ]  … Arch=ARM64 (exited-with-subordinates)`
@Suite struct LSAppInfoParserTests {

    /// One "N) "Name" ASN:…" entry block, shaped like real `lsappinfo list` text.
    /// `pidLineSuffix` is everything on the `pid = …` line after `Arch=ARM64 `,
    /// which is where both the quoted-or-not `Version` and the
    /// `(exited-with-subordinates)` marker (when present) actually live.
    private func entry(number: Int, name: String, bundleID: String, path: String, pidLineSuffix: String) -> String {
        """
         \(number)) "\(name)" ASN:0x0-0x18fb8fa:
            bundleID="\(bundleID)"
            bundle path="\(path)"
            executable path="\(path)/Contents/MacOS/\(name)"
            pid = 32196 token=[sess=100019 pid=32196 uid:501,501,501 g:20,20 pV:3002] type="UIElement" flavor=3 Version=\(pidLineSuffix)
            checkin time = 2026/09/09 10:21:52 ( 12 minutes ago )
        """
    }

    // MARK: - Baseline: an ordinary running app is unaffected

    /// Mutation this pins: deleting the `(exited-with-subordinates)` guard
    /// entirely (i.e. reverting to the pre-#473 parser) must NOT make this red
    /// — an app with no tombstone marker has to keep working exactly as before.
    @Test func anOrdinaryRunningAppIsCaptured() {
        let text = entry(
            number: 1, name: "Xcode", bundleID: "com.apple.dt.Xcode",
            path: "/Applications/Xcode.app",
            pidLineSuffix: "\"16.0\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed ")
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Applications/Xcode.app"] == "16.0")
    }

    // MARK: - The tombstone itself

    /// The core fix. AndroMeld-shaped: `Version` IS quoted, so without the
    /// `(exited-with-subordinates)` guard this reads as a live running build —
    /// exactly the #473 failure (disk build compares newer than this frozen one
    /// forever). Mutation this pins: delete the
    /// `!line.contains("(exited-with-subordinates)")` clause in
    /// `LSAppInfoParser.runningBuildVersions` → this goes from `nil` to
    /// `"2608.29.0"`, i.e. red. Verified by actually deleting that clause and
    /// re-running: this test fails, the baseline above does not.
    @Test func quotedVersionTombstoneIsExcluded() {
        let text = entry(
            number: 149, name: "AndroMeld", bundleID: "com.catchingnow.andfiles",
            path: "/Applications/AndDrive.app",
            pidLineSuffix: "\"2608.29.0\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed (exited-with-subordinates)")
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Applications/AndDrive.app"] == nil)
    }

    /// Fixture guard, not a marker-guard mutation: this is the OTHER real shape
    /// measured (a non-sandboxed UIElement helper whose tombstone carries
    /// `Version=[ NULL ]`, unquoted). `quotedValue` already returns `nil` for an
    /// unquoted value regardless of the marker, so this can't go red by
    /// deleting the marker guard alone — it grounds the parser against the
    /// shape actually observed rather than assuming quoting is universal.
    @Test func unquotedVersionTombstoneIsAlsoExcluded() {
        let text = entry(
            number: 35, name: "ClaudeWakeHost", bundleID: "",
            path: "/Users/bobby/Applications/ClaudeWakeHost.app",
            pidLineSuffix: "[ NULL ]  fileType=\"APPL\" creator=\"aplt\" Arch=ARM64 (exited-with-subordinates)")
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Users/bobby/Applications/ClaudeWakeHost.app"] == nil)
    }

    // MARK: - Interaction with "first entry wins"

    /// `runningBuildVersions` keeps the FIRST version seen per path (so a
    /// later, unrelated re-listing can't clobber an earlier read). That rule
    /// predates the tombstone guard and must compose with it correctly: a
    /// skipped (tombstone) block must NOT count as "already recorded", or the
    /// live entry that follows it would never get in. This is also the order
    /// #473 actually hit — a bundle path reported once, with the tombstone's
    /// own entry the only one LaunchServices had. Mutation this pins: deleting
    /// the `!line.contains("(exited-with-subordinates)")` clause (the same
    /// mutation `quotedVersionTombstoneIsExcluded` catches) makes the tombstone
    /// satisfy `map[cur] == nil` and claim the slot first — verified by
    /// deleting that clause and re-running: this and
    /// `quotedVersionTombstoneIsExcluded` are the only two of these six tests
    /// that go red, this one from `nil` to `"9.9.9"` — locking out the live
    /// entry that follows, not `"1.2.3"`.
    @Test func aTombstoneBeforeTheLiveEntryDoesNotBlockIt() {
        let path = "/Applications/TwoInstances.app"
        let tombstone = entry(
            number: 1, name: "TwoInstances", bundleID: "com.example.two",
            path: path, pidLineSuffix: "\"9.9.9\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed (exited-with-subordinates)")
        let live = entry(
            number: 2, name: "TwoInstances", bundleID: "com.example.two",
            path: path, pidLineSuffix: "\"1.2.3\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed ")
        let map = LSAppInfoParser.runningBuildVersions(from: tombstone + "\n" + live)
        #expect(map[path] == "1.2.3")
    }

    /// The reverse order: once a LIVE version is recorded, a tombstone
    /// appearing later for the same path must not overwrite it with its own
    /// (frozen, possibly different) version. ⚠️ No corresponding single-line
    /// mutation of its own — verified: deleting the marker clause alone (the
    /// mutation the two tests above pin) leaves this one green, because the
    /// pre-existing `map[cur] == nil` first-wins check already blocks the
    /// second write regardless of the marker (`live` claims the slot before
    /// `tombstone` is ever read). This order was never actually broken by
    /// #473 — only tombstone-before-live was. Kept as a fixture guard: it
    /// pins that first-wins composes safely with the new marker check in
    /// BOTH orders, not just the one #473 hit.
    @Test func aTombstoneAfterTheLiveEntryDoesNotOverwriteIt() {
        let path = "/Applications/TwoInstancesReversed.app"
        let live = entry(
            number: 1, name: "TwoInstancesReversed", bundleID: "com.example.two",
            path: path, pidLineSuffix: "\"1.2.3\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed ")
        let tombstone = entry(
            number: 2, name: "TwoInstancesReversed", bundleID: "com.example.two",
            path: path, pidLineSuffix: "\"9.9.9\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed (exited-with-subordinates)")
        let map = LSAppInfoParser.runningBuildVersions(from: live + "\n" + tombstone)
        #expect(map[path] == "1.2.3")
    }

    // MARK: - Path normalization still applies

    /// The map is keyed through `UpdatePolicy.runtimeBundlePath`, the same
    /// normalizer `computeRestartInfo`'s lookup key goes through — a staged
    /// component in the reported path must still be stripped for a live entry.
    /// Not itself a #473 regression guard (pre-existing behavior), included so
    /// this file is the one place asserting the parser's full contract.
    @Test func stagedPathComponentIsNormalizedForALiveEntry() {
        let text = entry(
            number: 1, name: "Staged", bundleID: "com.example.staged",
            path: "/Applications/.duoupdater-staged-Staged.app",
            pidLineSuffix: "\"4.0\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed ")
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Applications/Staged.app"] == "4.0")
    }

    // MARK: - The marker's position within a record

    /// Mutation this pins: committing the version the moment its line is read
    /// (`map[cur] = version` inline, i.e. both the pre-review implementation and the
    /// original pre-#473 one) — then the marker arrives too late and Ghost is recorded
    /// as a live 1.0.0 build, which is #473 verbatim.
    ///
    /// Every record measured so far carries the marker on the SAME line as `Version`,
    /// where a cursor-clearing guard would also have worked. This case covers the half
    /// of the format we have no observation of: a marker that trails `Version` on a
    /// later line. It is deliberately synthetic — `lsappinfo` has not been seen emitting
    /// this shape, and the point is that the parser must not depend on it not doing so.
    ///
    /// The second entry is not decoration: it pins that cancelling a record does not
    /// swallow the one that follows it, which is the way a hold-and-commit parser breaks
    /// if the commit boundary is placed wrong.
    @Test func aMarkerOnALaterLineStillCancelsTheRecord() {
        let text = """
         1) "Ghost" ASN:0x0-0x1:
            bundleID="com.example.ghost"
            bundle path="/Applications/Ghost.app"
            pid = 999 token=[sess=100019 pid=999] type="UIElement" flavor=3 Version="1.0.0" fileType="APPL" Arch=ARM64 sandboxed
            \(LSAppInfoParser.tombstoneMarker)
         2) "Live" ASN:0x0-0x2:
            bundleID="com.example.live"
            bundle path="/Applications/Live.app"
            pid = 1000 token=[sess=100019 pid=1000] type="UIElement" flavor=3 Version="2.0.0" fileType="APPL" Arch=ARM64 sandboxed
        """
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Applications/Ghost.app"] == nil)
        #expect(map["/Applications/Live.app"] == "2.0.0")
    }
}
