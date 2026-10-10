import Testing
import Foundation
@testable import DuoUpdaterCore

/// `update.vivaldi.com/update/1.0/relnotes/8.2.4133.84.html` as served (fetched
/// 2026-10-08), the `<style>` block dropped and the history after the second
/// section trimmed. The intro names the build here, but most pages' intros do not.
private let vivaldiMinorUpdateFixture = """
<html>
<head>
  <title>Vivaldi Changelog</title>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
</head>
<body>

<h2>A minor update to the stable release of Vivaldi has arrived [8.2.4133.84]!</h2>

<p>Get the full story by visiting the Vivaldi Desktop Updates blog: &lt;https://vivaldi.com/blog/desktop/updates&gt;</p>

<h2>Changelog since Vivaldi 8.2 (4133.83)</h2>
<ul class="latestchanges">
\t<li>[Chromium] Update to 152.0.7977.160 ESR <span>includes security fixes from 155.0.8059.39/40</span></li>
</ul>

<h2>Changelog since Vivaldi 8.2 (4133.80)</h2>
<ul>
\t<li>[Chromium] Update to 152.0.7977.155 ESR <span>includes security fixes from 154.0.8037.97/98</span></li>
</ul>

<h2>Changelog since Vivaldi 8.2 (4133.76)</h2>
<ul>
\t<li>[Chromium] Update to 152.0.7977.151 ESR <span>includes security fixes from 154.0.8037.92/93</span></li>
\t<li>[Linux] Silence harmless, "broken pipe" warnings when running update-ffmpeg</li>
</ul>
</body>
</html>
"""

/// `relnotes/8.2.4133.45.html` (fetched 2026-10-08), the first build of 8.2,
/// trimmed to three of its 58 changes: one section, and an intro that names no
/// build at all.
private let vivaldiMajorReleaseFixture = """
<body>

<h2>The stable release of Vivaldi 8.2 has arrived!</h2>

<p>Get the full story by visiting the Vivaldi blog &lt;vivaldi.com/blog/desktop&gt;</p>

<h2>Changelog since Vivaldi 8.1 (4087.75)</h2>
<ul class="latestchanges">
\t<li>[New][Address field][Calculator] Allow calculations in the adress field <span>VB-130090</span></li>
\t<li>[Address field][Tabs] Can’t click to focus address bar when tabs on side <span>VB-130428</span></li>
\t<li>[Widgets] Custom Background Style not applied <span>VB-129111</span></li>
</ul>
</body>
</html>
"""

/// What `update.vivaldi.com` answers, under a 404, for a build it has no page for.
private let vivaldiMissingPageBody = """
<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx/1.24.0 (Ubuntu)</center>
</body>
</html>
"""

@Suite struct VivaldiChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.vivaldi.Vivaldi"))
    }

    /// The page the feed links for a version is the one the template builds.
    @Test func thePageIsTheOneTheFeedLinks() throws {
        #expect(try recipe().resolvedSource(forVersion: "8.2.4133.84").absoluteString
            == "https://update.vivaldi.com/update/1.0/relnotes/8.2.4133.84.html")
    }

    /// Only this build's list: the earlier sections of the cumulative page stay
    /// out, and the entry is named by the requested version, not by the build the
    /// heading measures from.
    @Test func takesOnlyTheNewestSection() throws {
        let log = try #require(ChangelogService.parse(
            try recipe(), body: vivaldiMinorUpdateFixture, version: "8.2.4133.84"))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "8.2.4133.84")
        #expect(entry.date == nil)
        #expect(entry.content == [
            .heading("Changelog since Vivaldi 8.2 (4133.83)"),
            .note("[Chromium] Update to 152.0.7977.160 ESR includes security fixes from 155.0.8059.39/40"),
        ])
    }

    @Test func readsAPageWhoseIntroNamesNoBuild() throws {
        let log = try #require(ChangelogService.parse(
            try recipe(), body: vivaldiMajorReleaseFixture, version: "8.2.4133.45"))
        let entry = try #require(log.entries.first)
        #expect(log.entries.count == 1)
        #expect(entry.version == "8.2.4133.45")
        #expect(entry.items == [
            "[New][Address field][Calculator] Allow calculations in the adress field VB-130090",
            "[Address field][Tabs] Can’t click to focus address bar when tabs on side VB-130428",
            "[Widgets] Custom Background Style not applied VB-129111",
        ])
    }

    @Test func withoutAVersionNothingIsExtracted() throws {
        #expect(ChangelogService.parse(try recipe(), body: vivaldiMinorUpdateFixture) == nil)
    }

    @Test func aMissingPageIsNotRead() throws {
        #expect(ChangelogService.parse(
            try recipe(), body: vivaldiMissingPageBody, version: "8.2.4133.99") == nil)
    }

    /// Vivaldi Snapshot is its own bundle id with its own pages
    /// (`relnotes/snapshot/<version>.html`), so the Stable recipe never reaches it.
    @Test func snapshotIsNotGivenTheStablePages() throws {
        let snapshot = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.vivaldi.Vivaldi.snapshot", channel: .preview))
        #expect(snapshot.bundleID == "com.vivaldi.Vivaldi.snapshot")
        #expect(snapshot.resolvedSource(forVersion: "8.3.4175.3").absoluteString
            == "https://update.vivaldi.com/update/1.0/relnotes/snapshot/8.3.4175.3.html")
    }
}

/// `relnotes/snapshot/8.3.4175.3.html` as served (fetched 2026-10-10), the
/// `<style>` block dropped and its ten changes cut to three. A snapshot page has
/// no intro and one section, measured from the previous snapshot build.
private let vivaldiSnapshotFixture = """
\u{FEFF}<html>
<head>
  <title>Vivaldi Snapshot Changelog</title>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
  <meta name="robots" content="anchors">
</head>
<body>
<h2>Changelog since version 4171.3</h2>
<ul>
\t<li>[Ad Blocker] Check for invalid rule lists before parsing them <span>VB-132030</span></li>
\t<li>[Ad Blocker] Resetting a level should reset the document an first-party blocking settings for that level <span>VB-131986</span></li>
\t<li>[UI] CSS cleanup: could cause regressions <span>VB-132024</span></li>
</ul>
</body>
</html>
"""

@Suite struct VivaldiSnapshotChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.vivaldi.Vivaldi.snapshot", channel: .preview))
    }

    /// The page the snapshot feed links for a version is the one the template
    /// builds (`<sparkle:releaseNotesLink>` of the 8.3.4185.3 item, 2026-10-10).
    /// Mutation: drop `snapshot/` from `sourceTemplate` — the Stable path, which
    /// has no snapshot builds.
    @Test func thePageIsTheOneTheFeedLinks() throws {
        #expect(try recipe().resolvedSource(forVersion: "8.3.4185.3").absoluteString
            == "https://update.vivaldi.com/update/1.0/relnotes/snapshot/8.3.4185.3.html")
    }

    /// Only the page's one section, named by the requested version rather than
    /// the build its heading measures from.
    @Test func readsTheSnapshotPage() throws {
        let log = try #require(ChangelogService.parse(
            try recipe(), body: vivaldiSnapshotFixture, version: "8.3.4175.3"))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "8.3.4175.3")
        #expect(entry.date == nil)
        #expect(entry.items.count == 3)
        #expect(entry.content.first == .heading("Changelog since version 4171.3"))
        #expect(entry.items.first == "[Ad Blocker] Check for invalid rule lists before parsing them VB-132030")
    }

    @Test func withoutAVersionNothingIsExtracted() throws {
        #expect(ChangelogService.parse(try recipe(), body: vivaldiSnapshotFixture) == nil)
    }

    @Test func aMissingPageIsNotRead() throws {
        #expect(ChangelogService.parse(
            try recipe(), body: vivaldiMissingPageBody, version: "8.3.4185.99") == nil)
    }
}
