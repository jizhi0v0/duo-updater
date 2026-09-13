import Testing
import Foundation
@testable import DuoUpdaterCore

/// `…/update-notes-html/3.0.8/zh-Hans.html`, captured 2026-09-13, with only the
/// inline `<style>` block and blank lines removed. Translated pages open with an
/// "AI translated" notice before the first `<hr />`; sub-bullets are nested `<ul>`.
private let listPageFixture = #"""
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-Hans" xml:lang="zh-Hans">
<head>
  <meta charset="utf-8" />
  <meta name="generator" content="pandoc" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
  <title>3.0.8</title>
  <link rel="stylesheet" href="https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/html-assets/style.css"/>
  <script src="https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/html-assets/script.js"></script>
</head>
<body>
<p><strong>ℹ️ AI 翻译</strong></p>
<p>此发行说明由 Claude AI 翻译。可能包含错误。<br />
查看英文原版，请<a
href="https://github.com/noah-nuebling/mac-mouse-fix/releases/tag/3.0.8">点击这里</a>。</p>
<hr />
<p>Mac Mouse Fix <strong>3.0.8</strong> 解决了界面问题及其他问题。</p>
<h3 id="界面问题"><strong>界面问题</strong></h3>
<ul>
<li>在 macOS 26 Tahoe 上禁用了新设计。现在应用程序的外观和功能将与 macOS
15 Sequoia 上保持一致。
<ul>
<li>这样做是因为苹果重新设计的一些界面元素仍存在问题。例如，“按钮”选项卡上的”-“按钮有时无法点击。</li>
<li>现在在 macOS 26 Tahoe
上界面可能看起来有点过时。但功能应该完整且像以前一样完善。</li>
</ul></li>
<li>修复了”免费使用期已结束”通知卡在屏幕右上角的错误。
<ul>
<li>感谢 <a href="https://github.com/Sashpuri">Sashpuri</a>
和其他人的反馈！</li>
</ul></li>
</ul>
<h3 id="界面优化"><strong>界面优化</strong></h3>
<ul>
<li>禁用了 Mac Mouse Fix 主窗口中的绿色信号灯按钮。
<ul>
<li>由于窗口无法手动调整大小，该按钮没有任何作用。</li>
</ul></li>
<li>修复了在 macOS 26 Tahoe
下”按钮”选项卡中表格的一些水平线过暗的问题。</li>
<li>修复了在 macOS 26 Tahoe
下”按钮”选项卡上”无法使用主鼠标按钮”的消息有时会被截断的错误。</li>
<li>修复了德语界面中的一处拼写错误。感谢 GitHub 用户 <a
href="https://github.com/i-am-the-slime">i-am-the-slime</a>！</li>
<li>解决了在 macOS 26 Tahoe 上打开窗口时，MMF
窗口有时会短暂闪现错误尺寸的问题。</li>
</ul>
<h3 id="其他更改"><strong>其他更改</strong></h3>
<ul>
<li>改进了当计算机上运行多个 Mac Mouse Fix 实例时尝试启用 Mac Mouse Fix
的行为。
<ul>
<li>Mac Mouse Fix 现在会更加努力地尝试禁用其他 Mac Mouse Fix 实例。</li>
<li>这可能会改善某些无法启用 Mac Mouse Fix 的极端情况。</li>
</ul></li>
<li>底层更改和清理。</li>
</ul>
<hr />
<p>另外查看前一版本 <a
href="https://redirect.macmousefix.com/?target=mmf-release&amp;tag=3.0.7&amp;locale=zh-Hans">3.0.7</a>
的新功能。</p>
</body>
</html>
"""#

/// `…/update-notes-html/3.0.8/en.html`, captured 2026-09-13 and trimmed the same
/// way. Published but linked by neither feed today, and the one shape with no
/// translation notice: its only `<hr />` introduces the "previous release" footer.
private let untranslatedPageFixture = #"""
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="generator" content="pandoc" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
  <title>3.0.8</title>
  <link rel="stylesheet" href="https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/html-assets/style.css"/>
  <script src="https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/html-assets/script.js"></script>
</head>
<body>
<p>Mac Mouse Fix <strong>3.0.8</strong> solves UI issues and more.</p>
<h3 id="ui-issues"><strong>UI Issues</strong></h3>
<ul>
<li>Disabled the new design on macOS 26 Tahoe. Now the app will look and
function like it did on macOS 15 Sequoia.
<ul>
<li>I did this because some of Apple’s redesigned UI elements still have
issues. For example, the ‘-’ buttons on the ‘Buttons’ tab weren’t always
clickable.</li>
<li>The UI may look a little outdated on macOS 26 Tahoe now. But it
should be fully functional and polished just like before.</li>
</ul></li>
<li>Fixed a bug where the ‘Free days are over’ notification would get
stuck in the top-right screen corner.
<ul>
<li>Thanks to <a href="https://github.com/Sashpuri">Sashpuri</a> and
others for reporting it!</li>
</ul></li>
</ul>
<h3 id="ui-polish"><strong>UI Polish</strong></h3>
<ul>
<li>Disabled the green traffic light button in the main Mac Mouse Fix
window.
<ul>
<li>The button didn’t do anything, since the window cannot be resized
manually.</li>
</ul></li>
<li>Fixed an issue where some of the horizontal lines in the table on
the ‘Buttons’ tab were too dark under macOS 26 Tahoe.</li>
<li>Fixed a bug where the “Primary Mouse Button can’t be used” message
on the ‘Buttons’ tab would sometimes be cut off under macOS 26
Tahoe.</li>
<li>Fixed a typo in the German interface. Courtesy of GitHub user <a
href="https://github.com/i-am-the-slime">i-am-the-slime</a>.
Thanks!</li>
<li>Solved an issue where the MMF window would sometimes briefly flash
at the wrong size when opening the window on macOS 26 Tahoe.</li>
</ul>
<h3 id="other-changes"><strong>Other Changes</strong></h3>
<ul>
<li>Improved behavior when trying to enable Mac Mouse Fix while multiple
instances of Mac Mouse Fix are running on the computer.
<ul>
<li>Mac Mouse Fix will now try to disable the other instance of Mac
Mouse Fix more diligently.</li>
<li>This may improve edge cases where Mac Mouse Fix could not be
enabled.</li>
</ul></li>
<li>Under-the-hood changes and cleanup.</li>
</ul>
<hr />
<p>Also check out what’s new in the previous version <a
href="https://github.com/noah-nuebling/mac-mouse-fix/releases/tag/3.0.7">3.0.7</a>.</p>
</body>
</html>
"""#

/// `…/update-notes-html/2.1.0/de.html`, captured 2026-09-13, trimmed the same
/// way: one of the three measured pages with no `<li>` at all.
private let prosePageFixture = #"""
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="de" xml:lang="de">
<head>
  <meta charset="utf-8" />
  <meta name="generator" content="pandoc" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
  <title>2.1.0</title>
  <link rel="stylesheet" href="https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/html-assets/style.css"/>
  <script src="https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/html-assets/script.js"></script>
</head>
<body>
<p><strong>ℹ️ Von KI übersetzt</strong></p>
<p>Diese Versionshinweise wurden von der Claude KI übersetzt. Sie können
Fehler enthalten.<br />
Die englische Originalversion findest du <a
href="https://github.com/noah-nuebling/mac-mouse-fix/releases/tag/2.1.0">hier</a>.</p>
<hr />
<p>Schau dir auch die <strong>coolen Features</strong> an, die in <a
href="https://redirect.macmousefix.com/?target=mmf-release&amp;tag=2.0.0&amp;locale=de">Mac
Mouse Fix 2</a> eingeführt wurden!</p>
<hr />
<h3 id="die-app-funktioniert-wieder.">Die App funktioniert wieder.</h3>
<p>Ich habe die App mit einem neuen Zertifikat signiert. Das alte
Zertifikat wurde von Apple widerrufen, wodurch alte Versionen von Mac
Mouse Fix unbrauchbar werden. Mehr Infos findest du in <a
href="https://github.com/noah-nuebling/mac-mouse-fix/discussions/114">diesem
Beitrag</a>.</p>
<h3 id="neues-feature">Neues Feature!</h3>
<p>Du kannst jetzt direkt von deiner Maus aus <strong>Medien
abspielen</strong>, <strong>Lautstärke regeln</strong>,
<strong>Bildschirmhelligkeit einstellen</strong> und vieles mehr! Das
ist möglich, weil Mac Mouse Fix dir nun erlaubt, deine Maustasten mit
jeder beliebigen Taste deiner Tastatur zu belegen - sogar mit Apples
speziellen Funktionstasten wie “Play-Pause” oder “Ton aus”.</p>
<p><img width="500px" src="https://user-images.githubusercontent.com/40808343/148666688-f2da6897-a6d2-47cb-86df-59afb3ab8682.gif"></p>
</body>
</html>
"""#

/// The stable appcast, captured 2026-09-13, cut to two items and three of their
/// twelve languages. The OLDER item comes first on purpose, so a reader that
/// takes the first item in document order instead of the newest usable one
/// resolves 3.0.7's page and fails.
private let appcastFixture = #"""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"  xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
    <title>Mac Mouse Fix Update Feed</title>
    <link>https://raw.githubusercontent.com/noah-nuebling/mac-mouse-fix/update-feed/appcast.xml</link>
    <description>Stable releases of Mac Mouse Fix</description>
    <language>en</language>
    <item>
    <title>3.0.7 available!</title>
    <pubDate>2025-08-25T09:09:18Z</pubDate>
    <sparkle:minimumSystemVersion>10.15.0</sparkle:minimumSystemVersion>
    <sparkle:releaseNotesLink xml:lang="de">
        https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/docs/update-notes-html/3.0.7/de.html
    </sparkle:releaseNotesLink>
    <sparkle:releaseNotesLink xml:lang="zh-Hans">
        https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/docs/update-notes-html/3.0.7/zh-Hans.html
    </sparkle:releaseNotesLink>
    <sparkle:releaseNotesLink xml:lang="ko">
        https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/docs/update-notes-html/3.0.7/ko.html
    </sparkle:releaseNotesLink>
    <enclosure
        url="https://github.com/noah-nuebling/mac-mouse-fix/releases/download/3.0.7/MacMouseFixApp.zip"
        sparkle:version="24072"
        sparkle:shortVersionString="3.0.7"
        sparkle:edSignature="l3QdORp/wudEWPPEMkKE+NbA/MtWwexFdv+P4j2ctjl1Sx5POM57mxBZecd/M6/d40iYV4jpxFJA05626rM/CA==" length="7659508"
        type="application/octet-stream"
    />
</item>
    <item>
    <title>3.0.8 available!</title>
    <pubDate>2025-09-12T13:24:41Z</pubDate>
    <sparkle:minimumSystemVersion>10.15.0</sparkle:minimumSystemVersion>
    <sparkle:releaseNotesLink xml:lang="de">
        https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/docs/update-notes-html/3.0.8/de.html
    </sparkle:releaseNotesLink>
    <sparkle:releaseNotesLink xml:lang="zh-Hans">
        https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/docs/update-notes-html/3.0.8/zh-Hans.html
    </sparkle:releaseNotesLink>
    <sparkle:releaseNotesLink xml:lang="ko">
        https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/docs/update-notes-html/3.0.8/ko.html
    </sparkle:releaseNotesLink>
    <enclosure
        url="https://github.com/noah-nuebling/mac-mouse-fix/releases/download/3.0.8/MacMouseFixApp.zip"
        sparkle:version="24310"
        sparkle:shortVersionString="3.0.8"
        sparkle:edSignature="M12p9yzslfx+7Hko3e+Zl/udkll3Lm+GiQ44w5F2xGC+xG73BqW3/tcClRAG5xpKHFdGqUxLNC/uncUJr/z2BQ==" length="7614657"
        type="application/octet-stream"
    />
</item>
</channel>
</rss>
"""#

private let pageBase =
    "https://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/docs/update-notes-html/"

/// #557: a recipe whose page is the one the update source resolved, rather than
/// a URL in the registry.
@Suite struct MacMouseFixChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes
            .first { $0.bundleID == "com.nuebling.mac-mouse-fix" })
    }

    private func page(_ version: String, _ language: String) -> URL {
        URL(string: pageBase + "\(version)/\(language).html")!
    }

    private func result(changelogURL: URL?) -> UpdateResult {
        let app = InstalledApp(
            name: "ZZFixture MMF", bundleID: "com.nuebling.mac-mouse-fix",
            shortVersion: "3.0.7", buildVersion: "24072",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-MMF.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let remote = RemoteVersion(
            shortVersion: "3.0.8", version: "24310", downloadURL: nil,
            sourceName: "Sparkle", changelogURL: changelogURL)
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "3.0.8"))
    }

    // MARK: - The page

    /// The notice is `<p>`, not `<li>`, so on a list page it is the item
    /// pattern's order that keeps it out; on a prose page it is where `body`
    /// starts (see `aProseOnlyPageFallsThroughToParagraphs`). Mutation: remove
    /// `headingPattern` — the three headings disappear.
    @Test func readsTheListPageWithoutTheTranslationNotice() throws {
        let log = try #require(ChangelogExtractor.extract(from: listPageFixture, using: try recipe()))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == "3.0.8")
        #expect(entry.items.count == 15)
        #expect(!entry.items.contains { $0.contains("Claude AI") })
        #expect(entry.content.filter { if case .heading = $0 { true } else { false } }.count == 3)
    }

    /// Mutation: item pattern `<li>(?<item>.*?)</li>` — the parent line swallows
    /// its first sub-bullet, and the two are one line.
    @Test func aSubBulletIsNotMergedIntoItsParent() throws {
        let log = try #require(ChangelogExtractor.extract(from: listPageFixture, using: try recipe()))
        let items = try #require(log.entries.first).items
        #expect(items.first == "在 macOS 26 Tahoe 上禁用了新设计。现在应用程序的外观和功能将与 macOS 15 Sequoia 上保持一致。")
        #expect(items.dropFirst().first?.hasPrefix("这样做是因为") == true)
    }

    /// Mutation: skip to the first `<hr />` instead of past the notice, and the
    /// body becomes the footer: one item, "Also check out what’s new in the
    /// previous version 3.0.7." (measured on the real page).
    @Test func aPageWithoutTheNoticeKeepsItsNotes() throws {
        let log = try #require(ChangelogExtractor.extract(from: untranslatedPageFixture, using: try recipe()))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "3.0.8")
        #expect(entry.items.count == 15)
        #expect(!entry.items.contains { $0.contains("previous version") })
    }

    /// Mutations: remove the `<p>` item pattern — this page extracts nothing and
    /// the pane embeds it instead; or drop the notice group from
    /// `entryPattern` — the translation notice becomes a change line.
    @Test func aProseOnlyPageFallsThroughToParagraphs() throws {
        let log = try #require(ChangelogExtractor.extract(from: prosePageFixture, using: try recipe()))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "2.1.0")
        #expect(entry.items.count == 3)
        #expect(!entry.items.contains { $0.contains("Von KI übersetzt") })
    }

    // MARK: - Which URL it may start from

    @Test func acceptsTheShapesTheFeedsPublish() throws {
        let recipe = try recipe()
        for (version, language) in [("3.0.8", "de"), ("3.0.8", "zh-Hant"), ("3.0.0-Beta-1.1", "pt-BR"),
                                    ("3.1.0-Beta-1", "zh-HK"), ("2.0.0-Beta-13", "ko")] {
            let url = page(version, language)
            #expect(recipe.acceptedFeedPage(url) == url, "\(url)")
        }
    }

    /// Mutation: in `acceptedFeedPage`, drop the `ChangelogURLPolicy` check —
    /// the credential-bearing URL goes through (the registry pattern alone
    /// rejects the rest, which is why the smuggled one is tested separately).
    @Test func refusesEverythingElse() throws {
        let recipe = try recipe()
        for string in [
            "http://raw.githack.com/noah-nuebling/mac-mouse-fix/update-feed/docs/update-notes-html/3.0.8/de.html",
            "https://raw.githack.com/someone-else/mac-mouse-fix/update-feed/docs/update-notes-html/3.0.8/de.html",
            "https://github.com/noah-nuebling/mac-mouse-fix/releases/tag/3.0.8",
            pageBase + "3.0.8/de.html?x=1",
            pageBase + "3.0.8/de.md",
        ] {
            #expect(recipe.acceptedFeedPage(URL(string: string)!) == nil, "\(string)")
        }
        #expect(recipe.acceptedFeedPage(nil) == nil)

        // A pattern loose enough to admit credentials, so that only the policy
        // can be what refuses them.
        let loose = ChangelogRecipe(
            bundleID: "zz.fixture", source: URL(string: "https://zz.example/appcast.xml")!,
            entryPattern: "x", itemPatterns: ["x"],
            feedPagePattern: #"^https://[^?#]+\.html$"#)
        let plain = URL(string: "https://raw.githack.com/zz/de.html")!
        #expect(loose.acceptedFeedPage(plain) == plain)
        #expect(loose.acceptedFeedPage(URL(string: "https://user@raw.githack.com/zz/de.html")!) == nil)
    }

    /// Mutation: in `acceptedFeedPage`, accept any match rather than one spanning
    /// the whole string — a registry pattern that forgot its anchors then accepts
    /// a page named inside another host's query.
    @Test func aPatternWithoutAnchorsStillMatchesTheWholeURL() {
        let unanchored = ChangelogRecipe(
            bundleID: "zz.fixture", source: URL(string: "https://zz.example/appcast.xml")!,
            entryPattern: "x", itemPatterns: ["x"],
            feedPagePattern: #"https://raw\.githack\.com/[^?#]+\.html"#)
        let genuine = URL(string: "https://raw.githack.com/zz/de.html")!
        #expect(unanchored.acceptedFeedPage(genuine) == genuine)
        #expect(unanchored.acceptedFeedPage(
            URL(string: "https://zz.example/?u=https://raw.githack.com/zz/de.html")!) == nil)
    }

    /// Mutation: `pageURL` returns `acceptedFeedPage(feedPage) ?? source` — the
    /// appcast is then fetched as if it were the notes.
    @Test func withoutAPageThereIsNothingToFetch() throws {
        let recipe = try recipe()
        #expect(recipe.pageURL(forVersion: "3.0.8", feedPage: nil) == nil)
        #expect(recipe.pageURL(forVersion: "3.0.8",
                               feedPage: URL(string: "https://github.com/x/y")!) == nil)
        #expect(recipe.pageURL(forVersion: "3.0.8", feedPage: page("3.0.8", "de")) == page("3.0.8", "de"))
    }

    // MARK: - Selection

    /// Mutation: delete the `feedPagePattern` guard in
    /// `ChangelogRecipeSelection.recipe(for:)` — the recipe is offered with no
    /// page, and the model owns a load that can only fail.
    @Test func theRecipeIsInertWithoutAnAcceptedPage() throws {
        #expect(ChangelogRecipeSelection.recipe(for: result(changelogURL: nil)) == nil)
        let github = URL(string: "https://github.com/noah-nuebling/mac-mouse-fix/releases/tag/3.0.8")!
        #expect(ChangelogRecipeSelection.recipe(for: result(changelogURL: github)) == nil)

        let resolved = page("3.0.8", "zh-Hans")
        let offered = result(changelogURL: resolved)
        let recipe = try #require(ChangelogRecipeSelection.recipe(for: offered))
        #expect(ChangelogRecipeSelection.feedPage(for: offered, recipe: recipe) == resolved)
        // The fallback is still the same page, so a failed parse embeds exactly it.
        #expect(ChangelogRecipeSelection.fallbackPage(for: offered) == .fromSource(resolved))
    }

    /// A recipe with a fixed source ignores whatever the source resolved.
    @Test func aFixedSourceRecipeHasNoFeedPage() throws {
        let fixed = try #require(ChangelogRecipeRegistry.recipes.first { $0.feedPagePattern == nil })
        #expect(ChangelogRecipeSelection.feedPage(for: result(changelogURL: page("3.0.8", "de")),
                                                  recipe: fixed) == nil)
        #expect(ChangelogService.diskKey(for: fixed, version: "1.0", feedPage: page("3.0.8", "de"))?.page == nil)
    }

    // MARK: - Disk cache

    /// Mutation: `diskKey` ignores `feedPage` — both languages share one key.
    @Test func eachLanguageIsItsOwnDiskKey() throws {
        let recipe = try recipe()
        let german = ChangelogService.diskKey(for: recipe, version: "3.0.8", feedPage: page("3.0.8", "de"))
        let chinese = ChangelogService.diskKey(for: recipe, version: "3.0.8", feedPage: page("3.0.8", "zh-Hans"))
        #expect(german != nil && chinese != nil)
        #expect(german != chinese)
        #expect(ChangelogService.diskKey(for: recipe, version: "3.0.8", feedPage: nil) == nil)
    }

    /// The case #557 names: notes cached in one language must not be what the
    /// next launch serves a reader in another. A second cache instance over the
    /// same directory stands in for that launch, so the in-memory mirror cannot
    /// answer. Mutation: leave `page` out of `ChangelogDiskCache.fileURL`.
    @Test func anotherLanguageIsADiskMissAfterRelaunch() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMFChangelogDiskKey-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let recipe = try recipe()
        let german = try #require(
            ChangelogService.diskKey(for: recipe, version: "3.0.8", feedPage: page("3.0.8", "de")))
        let chinese = try #require(
            ChangelogService.diskKey(for: recipe, version: "3.0.8", feedPage: page("3.0.8", "zh-Hans")))
        let notes = Changelog(entries: [.init(version: "3.0.8", date: nil, items: ["Deutsch"])])
        await ChangelogDiskCache(directory: dir).set(notes, for: german)

        let relaunched = ChangelogDiskCache(directory: dir)
        #expect(await relaunched.get(for: german) == notes)
        #expect(await relaunched.get(for: chinese) == nil)
    }

    // MARK: - duo verify's own page

    /// What `loadDiagnostic` fetches when no page is handed in. Host-independent:
    /// which language comes back depends on the machine running this, so only
    /// the version and the recipe's acceptance are asserted. Mutation: take
    /// `.last` of the usable items, or skip `usableItems` and take the first
    /// item in document order — either resolves 3.0.7.
    @Test func verifyResolvesTheNewestItemsPageFromTheAppcast() throws {
        let recipe = try recipe()
        let link = try #require(SparkleAppcastSource.probeReleaseNotesLink(
            in: Data(appcastFixture.utf8), feedURL: recipe.source, bundleID: recipe.bundleID))
        #expect(recipe.acceptedFeedPage(link) == link)
        #expect(link.deletingLastPathComponent().lastPathComponent == "3.0.8")
    }
}
