import Testing
import Foundation
@testable import DuoUpdaterCore

/// `https://www.figma.com/release-notes/feed/atom.xml` as served (fetched
/// 2026-10-10), the feed header and the first two of its 459 entries, byte for
/// byte. No entry names a desktop build: the beta offered that day was 126.10.3.
private let figmaFeedFixture = #"""
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
    <id>https://www.figma.com/release-notes/</id>
    <title>Figma product news and release notes</title>
    <updated>2026-10-09T21:05:23.071Z</updated>
    <generator>https://github.com/jpmonette/feed</generator>
    <link rel="alternate" href="https://www.figma.com/release-notes/"/>
    <link rel="self" href="https://www.figma.com/release-notes/feed/atom.xml"/>
    <subtitle>Keep up-to-date with release notes and software updates for all Figma related products.</subtitle>

<entry>
        <title type="html"><![CDATA[The Figma agent is generally available ]]></title>
        <id>f3641297-2917-4a63-8b54-eb19182e07e9</id>
        <link href="https://www.figma.com/release-notes/?title=the-figma-agent-is-generally-available"/>
        <updated>2026-10-06T00:00:00.000Z</updated>
        <content type="html"><![CDATA[The Figma agent is exiting beta with improved latency, improved multiplayer performance, better access to Figma context, and a new tools to guide the agent's use of design libraries.]]></content>
    </entry>
<entry>
        <title type="html"><![CDATA[Connect multiple GitHub organizations to Figma]]></title>
        <id>eb3b1b06-a458-454a-9e9d-419bfb59e218</id>
        <link href="https://www.figma.com/release-notes/?title=connect-multiple-github-organizations-to-figma"/>
        <updated>2026-10-05T00:00:00.000Z</updated>
        <content type="html"><![CDATA[You can now connect multiple GitHub organizations to a single Figma plan.]]></content>
    </entry>
</feed>
"""#

/// Figma Beta reads the same product release-notes feed as stable: Figma
/// publishes no beta notes.
@Suite struct FigmaBetaChangelogRecipeTests {
    private func beta() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.figma.DesktopBeta", channel: .beta))
    }

    @Test func readsTheProductFeed() throws {
        let log = try #require(ChangelogService.parse(try beta(), body: figmaFeedFixture))
        #expect(log.entries.count == 2)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "The Figma agent is generally available")
        #expect(entry.date == "2026-10-06")
        #expect(entry.items == [
            "The Figma agent is exiting beta with improved latency, improved multiplayer performance, better access to Figma context, and a new tools to guide the agent's use of design libraries.",
        ])
    }

    /// No entry is a build, so the page is never judged behind the offered beta.
    @Test func aFeedWithNoBuildsIsNeverBehindTheOfferedBeta() throws {
        let log = try #require(ChangelogService.parse(try beta(), body: figmaFeedFixture))
        #expect(log.carries(version: "126.10.3"))
    }

    /// One feed, read one way: a fix to the stable recipe must reach the beta.
    @Test func readsTheFeedExactlyAsStableDoes() throws {
        let beta = try beta()
        let stable = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.figma.Desktop"))
        #expect(beta.source == stable.source)
        #expect(beta.entryPattern == stable.entryPattern)
        #expect(beta.itemPatterns == stable.itemPatterns)
        #expect(beta.maxEntries == stable.maxEntries)
    }
}
