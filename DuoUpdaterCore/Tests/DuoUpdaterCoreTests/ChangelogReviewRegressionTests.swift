import Testing
import Foundation
@testable import DuoUpdaterCore

/// Regressions found reviewing the structured-decoding batch. Each one is pinned
/// with the *real* bytes that exposed it, because every defect here was invisible
/// to the tests that shipped with the change: those asserted the shapes the new
/// code already handled. A fixture written from the implementation cannot catch
/// the implementation being wrong about the feed.

// MARK: - HBuilderX: Markdown inline code must not reach the user as backticks

/// Verbatim from `https://hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_release.md`
/// (fetched 2026-08-22). Four of the nine backticked items in the live top-10
/// window, plus a plain item and the trailing-link shapes, so this exercises the
/// interaction between link-consumption and code-span unwrapping rather than
/// either alone.
private let hbuilderXCodeSpanFixture = #"""
## 5.24.2026081301
* 新增 云打包 通过`CLI pack cancel`取消打包 [文档](https://hx.dcloud.net.cn/cli/pack) <https://issues.dcloud.net.cn/pages/issues/detail?id=30500>
* 新增 云打包 通过`CLI pack`支持广告等更多参数 [文档](https://hx.dcloud.net.cn/cli/pack) <https://issues.dcloud.net.cn/pages/issues/detail?id=30645>
* 修复 部分情况下编辑器卡顿的Bug [详情](https://issues.dcloud.net.cn/x)
* 新增 云打包 通过`CLI pack status`查询打包记录 [文档](https://hx.dcloud.net.cn/cli/pack?id=pack-query)

## 5.23.2026072902
* 新增 云打包 通过`CLI logcat pack`获取打包控制台日志 [文档](https://hx.dcloud.net.cn/cli/logcat-pack)
"""#

@Test func hbuilderXUnwrapsInlineCodeInsteadOfShowingBackticks() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "io.dcloud.HBuilderX"),
        "HBuilderX stable recipe must exist")
    let changelog = try #require(
        ChangelogExtractor.extract(from: hbuilderXCodeSpanFixture, using: recipe))

    let allItems = changelog.entries.flatMap(\.items)
    #expect(!allItems.isEmpty)
    // The whole point: the HTML source this replaced spelled these `<code>…</code>`
    // and `stripTags` removed the wrapper, so the migration must not start showing
    // the Markdown equivalent as punctuation.
    for item in allItems {
        #expect(!item.contains("`"), "backtick leaked into rendered note: \(item)")
    }
    // …while keeping the code TEXT, which is the part that carries the meaning.
    #expect(allItems.contains("新增 云打包 通过CLI pack cancel取消打包"))
    #expect(allItems.contains("新增 云打包 通过CLI logcat pack获取打包控制台日志"))
    // A plain item is untouched, and the trailing links are still consumed.
    #expect(allItems.contains("修复 部分情况下编辑器卡顿的Bug"))
}

@Test func markdownUnwrapLeavesUnpairedAndDoubleBackticksAlone() {
    // A span that never closes is not a span — leave the user's literal character.
    #expect(ChangelogExtractor.unwrapMarkdownInlineCode("cost is 50`") == "cost is 50`")
    // Double-backtick spans exist so the code text can itself contain a backtick.
    #expect(ChangelogExtractor.unwrapMarkdownInlineCode("run ``a `b` c`` now") == "run a `b` c now")
    // A span may not straddle a line break.
    #expect(ChangelogExtractor.unwrapMarkdownInlineCode("a`b\nc`d") == "a`b\nc`d")
}

/// The flag is opt-in: a recipe reading HTML must keep a literal backtick a
/// vendor typed. Pinning this from the registry rather than a hand-written list
/// so a future recipe that sets `markdownSource` shows up here.
@Test func onlyMarkdownSourceRecipesUnwrapCodeSpans() {
    let flagged = ChangelogRecipeRegistry.recipes.filter(\.markdownSource)
    #expect(flagged.allSatisfy { $0.source.path.hasSuffix(".md") },
            "markdownSource belongs on recipes whose body really is Markdown")
    #expect(!flagged.isEmpty, "HBuilderX stable + alpha should be flagged")
}

// MARK: - Postman: items keep the whitespace normalization the regex path had

/// Verbatim slice of `https://mkt.cdn.postman.com/www-next/release-notes/app-release-notes.json`
/// (fetched 2026-08-22) — the 12.19.0 note whose line carries a trailing space,
/// which is the exact byte the migration dropped on the floor.
@Test func postmanItemsAreWhitespaceNormalizedLikeTheRegexPathWas() {
    let items = StructuredChangelogDecoder.postmanItems(
        from: "Improved the experience of working with collections, environments, and API specifications. \r\n"
            + "Fixed  an  issue  where  the  sidebar  flickered.\r\n")
    #expect(items == [
        "Improved the experience of working with collections, environments, and API specifications.",
        "Fixed an issue where the sidebar flickered.",
    ])
}

/// The length floor must measure the *normalized* line, as `minItemLength` did
/// after `clean`. Otherwise a line of nothing but spaces clears a `>= 10` check
/// and renders as an empty bullet.
@Test func postmanLengthFloorMeasuresTheTrimmedLine() {
    #expect(StructuredChangelogDecoder.postmanItems(from: "             \r\nreal content here\r\n")
            == ["real content here"])
}

// MARK: - SunLogin: one malformed element must not take the whole feed down

/// Shape check, not a live-feed claim: today's payload is well formed. The point
/// is the *contract* — the file's own header promises "an entry with no usable
/// notes yields fewer entries", and a non-optional field turned that into all-or
/// -nothing, dropping the user back to the embedded web page.
@Test func sunLoginSkipsAMalformedEntryInsteadOfLosingTheFeed() throws {
    let body = #"""
    {"logs":[
      {"logs":"<ol><li>15.6.1</li><li>Fixed a crash on launch</li></ol>","updatedate":"2026-08-01 10:00:00"},
      {"logs":null,"updatedate":"2026-07-01 10:00:00"},
      {"logs":"<ol><li>15.6.0</li><li>Added remote print</li></ol>","updatedate":"2026-06-01 10:00:00"}
    ]}
    """#
    let changelog = try #require(StructuredChangelogDecoder.decodeSunLogin(body, maxEntries: 40))
    #expect(changelog.entries.map(\.version) == ["15.6.1", "15.6.0"])
    #expect(changelog.entries.first?.date == "2026-08-01")
}

/// A junk `updatedate` must not become a junk subtitle — the retired regex
/// required a `\d{4}-\d{2}-\d{2}` shape and dropped anything else.
@Test func sunLoginRejectsAMalformedDateRatherThanShowingIt() throws {
    let body = #"""
    {"logs":[{"logs":"<ol><li>15.6.1</li><li>Fixed a crash</li></ol>","updatedate":"soon"}]}
    """#
    let changelog = try #require(StructuredChangelogDecoder.decodeSunLogin(body, maxEntries: 40))
    #expect(changelog.entries.first?.date == nil)
}

/// Inner markup inside an `<li>` gets the same cleaning the retired recipe's
/// defaults (`stripTags: true, decodeEntities: true`) applied.
@Test func sunLoginCleansMarkupInsideAnItem() throws {
    let body = #"""
    {"logs":[{"logs":"<ol><li>15.6.1</li><li>Fixed <b>copy</b> &amp; paste in the <a href='#'>viewer</a></li></ol>","updatedate":"2026-08-01 10:00:00"}]}
    """#
    let changelog = try #require(StructuredChangelogDecoder.decodeSunLogin(body, maxEntries: 40))
    #expect(changelog.entries.first?.items == ["Fixed copy & paste in the viewer"])
}

// MARK: - Zed: a release with no bullets still gets an entry

/// `v1.5.3-pre`'s real body, verbatim (1 of the newest 100 releases on
/// 2026-08-22). `GitHubMarkdownParser` returns nil for it — no bullets — and the
/// retired zed.dev recipe had a `<p>` item pattern that covered exactly this, so
/// skipping it meant a Preview user on that build saw no entry for their own
/// installed version.
@Test func zedKeepsAReleaseWhoseNotesAreProseNotBullets() throws {
    let body = #"""
    {"tag_name":"v1.5.3-pre","prerelease":true,"published_at":"2026-05-14T12:00:00Z",
     "body":"No public-facing changes in this release. [View the commits](https://github.com/zed-industries/zed/compare/v1.5.2-pre...v1.5.3-pre)"}
    """#
    let feed = "[\(body)]"
    let changelog = try #require(StructuredChangelogDecoder.decodeZedGitHubReleases(feed, channel: .preview, maxEntries: 15))
    let entry = try #require(changelog.entries.first)
    #expect(entry.version == "1.5.3")
    // The Markdown link is KEPT rather than flattened: the entry carries
    // `.markdown` item syntax, so it renders as a link the reader can follow.
    // (The Zed-only fallback this replaced flattened it to bare text, which was
    // the wrong call for a `.markdown` entry.)
    #expect(entry.items == [
        "No public-facing changes in this release. "
            + "[View the commits](https://github.com/zed-industries/zed/compare/v1.5.2-pre...v1.5.3-pre)",
    ])
}

/// …but a body with nothing renderable at all is still skipped, rather than
/// producing a bare version heading with an empty bullet under it.
///
/// The fallback that makes the test above pass now lives in `GitHubMarkdownParser`
/// rather than in a Zed-only branch here — every GitHub-sourced app has the same
/// shape and deserves the same treatment. Asserted through the public parser so
/// this stays true wherever the implementation sits.
@Test func aReleaseWithNothingRenderableIsStillSkipped() {
    #expect(GitHubMarkdownParser.parse(
        body: "## Heading only\n\n### Another\n", version: "1.0", date: nil) == nil)
    #expect(GitHubMarkdownParser.parse(
        body: "   \n\n  \n", version: "1.0", date: nil) == nil)
}

// MARK: - ChatWise: CRLF must not fold a whole entry into one line

/// Swift treats "\r\n" as ONE Character that is not equal to "\n", so
/// `split(separator: "\n")` does not split a CRLF body at all. ChatWise's feed is
/// LF today; this pins the behavior so the day it isn't, the bug is a red test
/// rather than a changelog that silently renders as a single giant bullet.
@Test func bulletItemsSplitCRLFBodies() {
    #expect(StructuredChangelogDecoder.bulletItems(from: "- first item\r\n- second item\r\n")
            == ["first item", "second item"])
    #expect(StructuredChangelogDecoder.bulletItems(from: "- first item\n- second item\n")
            == ["first item", "second item"])
}

// MARK: - The structural invariant nothing was asserting

/// `structuredFormat` silently disables `indexLinkPattern` in `ChangelogService`
/// (a structured recipe makes one request, not two), and a recipe carrying both a
/// `structuredFormat` and an `entryPattern` would run only one of them. Neither
/// combination fails at compile time, and neither fails loudly at runtime — it
/// just quietly produces the wrong thing. Derived from the registry so a new
/// recipe cannot slip past.
@Test func noRecipeMixesTheStructuredAndRegexPaths() {
    for recipe in ChangelogRecipeRegistry.recipes where recipe.structuredFormat != nil {
        #expect(recipe.entryPattern.isEmpty,
                "\(recipe.bundleID): structuredFormat and entryPattern are mutually exclusive")
        #expect(recipe.indexLinkPattern == nil,
                "\(recipe.bundleID): structuredFormat skips the two-stage fetch, so indexLinkPattern is dead")
    }
}

// MARK: - Waku

/// Waku's registered recipe reads GitHub releases, which carry the same bullets
/// AND the history the per-version `.md` files can't enumerate (the site root
/// 404s, so there is no index to walk).
@Test func wakuReadsGitHubReleases() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "sh.waku"))
    #expect(recipe.structuredFormat == .gitHubReleases)
    #expect(recipe.source.host == "api.github.com")
}

/// The generic GitHub-releases decoder: stable only, newest first, `v` stripped,
/// and a prose-only release still gets an entry rather than a gap in the rail.
@Test func gitHubReleasesDecoderSkipsPrereleasesAndKeepsProseOnes() throws {
    let feed = #"""
    [{"tag_name":"v0.1.12","prerelease":false,"draft":false,"published_at":"2026-08-21T00:00:00Z",
      "body":"- Stream live output from Claude background tasks\n- Fix model selection for Cursor"},
     {"tag_name":"v0.2.0-rc1","prerelease":true,"draft":false,"published_at":"2026-08-21T00:00:00Z",
      "body":"- Something on a track the user did not choose"},
     {"tag_name":"v0.1.9","prerelease":false,"draft":false,"published_at":"2026-08-18T00:00:00Z",
      "body":"See CHANGELOG.md for details."}]
    """#
    let log = try #require(StructuredChangelogDecoder.decodeGitHubReleases(feed, maxEntries: 20))
    #expect(log.entries.map(\.version) == ["0.1.12", "0.1.9"])
    #expect(log.entries.first?.date == "2026-08-21")
    #expect(log.entries.last?.items == ["See CHANGELOG.md for details."])
}
