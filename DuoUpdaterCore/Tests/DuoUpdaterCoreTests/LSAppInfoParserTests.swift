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

    /// Every fixture path below must NOT exist on the machine running these tests.
    ///
    /// `runningBuildVersions` keys its map through `UpdatePolicy.runtimeBundlePath`,
    /// whose first act is `resolvingSymlinksInPath()`. For a path that does not exist
    /// that is the identity, so the key is exactly the string in the fixture. For one
    /// that DOES exist and is a symlink, it is not — and the assertion then compares
    /// against a key the parser never produced.
    ///
    /// This is not hypothetical. The first version of this suite used
    /// "/Applications/Xcode.app": green on the author's machine, which has no
    /// `Xcode.app` (it runs Xcode-beta), and RED on CI, whose runner image has one and
    /// resolves it elsewhere. The `== nil` cases are worse than the failing one,
    /// because they stay green either way: a key that drifts is simply absent from the
    /// map, so the case keeps passing while no longer exercising the tombstone rule at
    /// all. Two of them were pointed at real paths on this machine
    /// ("/Applications/AndDrive.app", the reporter's own app, and a real
    /// ClaudeWakeHost bundle).
    ///
    /// So: made-up names, and this guard so a future fixture cannot quietly
    /// reintroduce the dependency.
    private func assertFixturePathIsAbsent(_ path: String) {
        #expect(!FileManager.default.fileExists(atPath: path),
                "fixture path \(path) exists on this host — see assertFixturePathIsAbsent")
    }

    /// One "N) "Name" ASN:…" entry block, shaped like real `lsappinfo list` text.
    /// `pidLineSuffix` is everything on the `pid = …` line after `Arch=ARM64 `,
    /// which is where both the quoted-or-not `Version` and the
    /// `(exited-with-subordinates)` marker (when present) actually live.
    private func entry(number: Int, name: String, bundleID: String, path: String, pidLineSuffix: String) -> String {
        assertFixturePathIsAbsent(path)
        return """
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
            path: "/Applications/ZZFixture-Ordinary.app",
            pidLineSuffix: "\"16.0\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed ")
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Applications/ZZFixture-Ordinary.app"] == "16.0")
    }

    // MARK: - The tombstone itself

    /// The core fix. AndroMeld-shaped: `Version` IS quoted, so without the
    /// `(exited-with-subordinates)` guard this reads as a live running build —
    /// exactly the #473 failure (disk build compares newer than this frozen one
    /// forever). Mutation this pins (**M1**): delete the whole
    /// `else if line.contains(tombstoneMarker)` branch from
    /// `LSAppInfoParser.runningBuildVersions` → this goes from `nil` to
    /// `"2608.29.0"`, i.e. red. Measured 2026-09-09 by actually deleting that
    /// branch and re-running: M1 turns exactly three of this suite's seven cases
    /// red — this one, `aTombstoneBeforeTheLiveEntryDoesNotBlockIt`, and
    /// `aMarkerOnALaterLineStillCancelsTheRecord`.
    @Test func quotedVersionTombstoneIsExcluded() {
        let text = entry(
            number: 149, name: "AndroMeld", bundleID: "com.catchingnow.andfiles",
            path: "/Applications/ZZFixture-QuotedTombstone.app",
            pidLineSuffix: "\"2608.29.0\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed (exited-with-subordinates)")
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Applications/ZZFixture-QuotedTombstone.app"] == nil)
    }

    /// Fixture guard, not a marker-guard mutation: this is the OTHER real shape
    /// measured (a non-sandboxed UIElement helper whose tombstone carries
    /// `Version=[ NULL ]`, unquoted). `quotedValue` already returns `nil` for an
    /// unquoted value regardless of the marker, so this cannot go red under
    /// either M1 or M2 (measured: green under both) — it grounds the parser
    /// against the shape actually observed rather than assuming quoting is
    /// universal.
    @Test func unquotedVersionTombstoneIsAlsoExcluded() {
        let text = entry(
            number: 35, name: "ClaudeWakeHost", bundleID: "",
            path: "/Applications/ZZFixture-UnquotedTombstone.app",
            pidLineSuffix: "[ NULL ]  fileType=\"APPL\" creator=\"aplt\" Arch=ARM64 (exited-with-subordinates)")
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Applications/ZZFixture-UnquotedTombstone.app"] == nil)
    }

    // MARK: - Interaction with "first entry wins"

    /// `runningBuildVersions` keeps the FIRST version seen per path (so a
    /// later, unrelated re-listing can't clobber an earlier read). That rule
    /// predates the tombstone guard and must compose with it correctly: a
    /// skipped (tombstone) block must NOT count as "already recorded", or the
    /// live entry that follows it would never get in. This is also the order
    /// #473 actually hit — a bundle path reported once, with the tombstone's
    /// own entry the only one LaunchServices had. Mutation this pins (**M1**,
    /// the same one `quotedVersionTombstoneIsExcluded` catches): deleting the
    /// whole `else if line.contains(tombstoneMarker)` branch lets the tombstone
    /// be held and committed first, so `map[path] == nil` at commit time is no
    /// longer true when the live entry arrives — measured: this goes to
    /// `"9.9.9"`, locking out the live entry that follows, not `"1.2.3"`.
    @Test func aTombstoneBeforeTheLiveEntryDoesNotBlockIt() {
        let path = "/Applications/ZZFixture-TwoInstances.app"
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
    /// (frozen, possibly different) version. ⚠️ **No mutation of its own** —
    /// measured: both M1 (deleting the marker branch) and M2 (see
    /// `aMarkerOnALaterLineStillCancelsTheRecord`) leave this one green, because
    /// first-wins already blocks the second write regardless of the marker: the
    /// live record is committed when the tombstone's `bundle path` line opens the
    /// next record, so `map[path] == nil` is already false by the time the
    /// tombstone could be held. This order was never actually broken by #473 —
    /// only tombstone-before-live was. Kept as a fixture guard: it pins that
    /// first-wins composes safely with the marker check in BOTH orders, not just
    /// the one #473 hit.
    @Test func aTombstoneAfterTheLiveEntryDoesNotOverwriteIt() {
        let path = "/Applications/ZZFixture-TwoInstancesReversed.app"
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
            path: "/Applications/.duoupdater-staged-ZZFixture-Staged.app",
            pidLineSuffix: "\"4.0\"  fileType=\"APPL\" creator=\"????\" Arch=ARM64 sandboxed ")
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Applications/ZZFixture-Staged.app"] == "4.0")
    }

    // MARK: - The marker's position within a record

    /// Mutation this pins (**M2**): committing the version the moment its line is read
    /// (`map[cur] = version` inline, i.e. both the pre-review implementation and the
    /// original pre-#473 one) — then the marker arrives too late and Ghost is recorded
    /// as a live 1.0.0 build, which is #473 verbatim. Measured 2026-09-09: **M2 turns
    /// this case and only this case red**; the other six stay green, because every
    /// other fixture has the marker on the same line as `Version`, where committing
    /// early and clearing a cursor are indistinguishable. It also goes red under M1.
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
        // Built by hand rather than via `entry`, so it needs the guard explicitly.
        assertFixturePathIsAbsent("/Applications/ZZFixture-Ghost.app")
        assertFixturePathIsAbsent("/Applications/ZZFixture-Live.app")
        let text = """
         1) "Ghost" ASN:0x0-0x1:
            bundleID="com.example.ghost"
            bundle path="/Applications/ZZFixture-Ghost.app"
            pid = 999 token=[sess=100019 pid=999] type="UIElement" flavor=3 Version="1.0.0" fileType="APPL" Arch=ARM64 sandboxed
            \(LSAppInfoParser.tombstoneMarker)
         2) "Live" ASN:0x0-0x2:
            bundleID="com.example.live"
            bundle path="/Applications/ZZFixture-Live.app"
            pid = 1000 token=[sess=100019 pid=1000] type="UIElement" flavor=3 Version="2.0.0" fileType="APPL" Arch=ARM64 sandboxed
        """
        let map = LSAppInfoParser.runningBuildVersions(from: text)
        #expect(map["/Applications/ZZFixture-Ghost.app"] == nil)
        #expect(map["/Applications/ZZFixture-Live.app"] == "2.0.0")
    }
}
