import Testing
import Foundation
@testable import DuoUpdaterCore

/// Two items from `releases.1password.com/mac/stable/index.xml`, captured
/// verbatim 2026-08-16. Order is the feed's own: ASCENDING, so the 2022 release
/// comes first and the current one last. The change list is entity-escaped
/// inside `<description>`, and prose entities are escaped twice
/// (`&amp;rsquo;`) — both are what this recipe has to survive.
private let onePasswordFeedFixture = #"""
<rss version="2.0"><channel><title>1Password for Mac - 1Password Releases</title>
<item><title>1Password for Mac 8.7.0</title><link>https://releases.1password.com/mac/stable/8.7.0/</link><pubDate>Tue, 03 May 2022 00:00:00 +0000</pubDate><guid>https://releases.1password.com/mac/stable/8.7.0/</guid><description>&lt;ul&gt;
&lt;li&gt;Everything is new! 🥰&lt;/li&gt;
&lt;/ul&gt;</description></item>
<item><title>1Password for Mac 8.12.33</title><link>https://releases.1password.com/mac/stable/8.12.33/</link><pubDate>Wed, 12 Aug 2026 00:00:00 +0000</pubDate><guid>https://releases.1password.com/mac/stable/8.12.33/</guid><description>&lt;ul&gt;
&lt;li&gt;We&amp;rsquo;ve fixed an issue where the &lt;a href="https://support.1password.com/"&gt;browser extension&lt;/a&gt; couldn&amp;rsquo;t connect. [[!40819]] &lt;/li&gt;
&lt;/ul&gt;</description></item>
</channel></rss>
"""#

@Suite struct OnePasswordFeedTests {
    private func changelog() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes
            .first { $0.bundleID == "com.1password.1password" })
    }

    private func probe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes
            .first { $0.bundleID == "com.1password.1password" })
    }

    /// The feed is ascending, so the probe must compare numerically. First-match
    /// here would report the 2022 release as current — which the UI renders as
    /// "up to date", forever, with nothing failing.
    @Test func theProbeTakesTheHighestVersionNotTheFirst() throws {
        let probe = try probe()
        #expect(probe.selectHighest)
        #expect(probe.url.absoluteString.hasSuffix("index.xml"))
        #expect(VendorProbeRecipe.extractVersion(
            from: onePasswordFeedFixture, pattern: probe.versionPattern) == "8.7.0",
            "first match is the OLDEST — selectHighest is what fixes it")
    }

    /// The install must never point at `1Password.zip`: that one holds
    /// `1Password Installer.app`, a signed, notarized stub. Every gate except the
    /// bundle-id check passes for it.
    @Test func theInstallURLIsThePayloadNotTheInstallerStub() throws {
        let spec = try #require(try probe().install)
        guard case .fixed(let url) = spec.urlSource else {
            Issue.record("expected a fixed URL"); return
        }
        #expect(url.absoluteString
            == "https://downloads.1password.com/mac/1Password-latest-aarch64.zip")
        #expect(!url.absoluteString.hasSuffix("/1Password.zip"))
        #expect(spec.kind == .zip)
    }

    @Test func newestReleaseComesFirstAfterFlipping() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: onePasswordFeedFixture, using: try changelog()))
        #expect(log.entries.first?.version == "8.12.33")
        #expect(log.entries.last?.version == "8.7.0")
    }

    /// The description is escaped HTML, so cleaning has to strip and decode twice:
    /// once for the escaping, once for what the escaping was hiding. Getting it
    /// wrong shows the user `<a href="…">` or a literal `&rsquo;`.
    @Test func escapedMarkupIsFullyUnwrapped() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: onePasswordFeedFixture, using: try changelog()))
        let item = try #require(log.entries.first?.items.first)
        #expect(item.contains("We’ve fixed"))
        #expect(item.contains("browser extension couldn’t connect"))
        #expect(!item.contains("<a href"))
        #expect(!item.contains("&rsquo;"))
        #expect(!item.contains("&lt;"))
    }
}
