import Testing
import Foundation
@testable import DuoUpdaterCore

/// WorkBuddy's two changelog pages. Both sites are the same VitePress build and
/// share one `entryPattern`, so these tests are written against BOTH fixtures
/// wherever the assertion is about the shared shape — a pattern that only ever
/// gets exercised on the Chinese page would not notice it breaking on the
/// English one, which is exactly the failure the shared constant exists to
/// prevent.
///
/// Fixtures are verbatim slices of the live pages: the CN ones fetched
/// 2026-08-27, the intl one 2026-10-03 (after that page's rebuild into
/// labelled lists, #913).
struct WorkBuddyChangelogTests {

    private static func recipe(_ bundleID: String) throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == bundleID },
                     "no changelog recipe registered for \(bundleID)")
    }

    private static let cnID = "com.workbuddy.workbuddy"
    private static let intlID = "com.workbuddy.workbuddy-ai"

    // MARK: - registration

    /// Each site's recipe reads its OWN site. The two apps have independent
    /// release trains, so showing one the other's notes would be wrong in a way
    /// no other check here could catch — and the two `source` URLs are one
    /// character apart.
    @Test func eachSiteReadsItsOwnChangelog() throws {
        #expect(try Self.recipe(Self.cnID).source.host() == "www.workbuddy.cn")
        #expect(try Self.recipe(Self.intlID).source.host() == "www.workbuddy.ai")
    }

    /// The whole reason the pattern is a shared constant: a fix applied to one
    /// site and not the other would leave them silently disagreeing.
    @Test func bothSitesShareOneEntryPattern() throws {
        #expect(try Self.recipe(Self.cnID).entryPattern
                == Self.recipe(Self.intlID).entryPattern)
        #expect(try Self.recipe(Self.cnID).headingPattern
                == Self.recipe(Self.intlID).headingPattern)
    }

    // MARK: - parsing the real pages

    @Test func readsTheChineseEntries() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: cnFixture, using: try Self.recipe(Self.cnID)))
        #expect(log.entries.count == 2)
        let first = try #require(log.entries.first)
        #expect(first.version == "5.3.14")
        #expect(first.date == "2026-08-17")
        #expect(first.items.count == 14)
        #expect(first.items.first?.hasPrefix("新增 Markdown AI 编辑快捷键提示") == true)
        // The anchor link that sits inside the heading must not leak into the text.
        #expect(!log.entries.contains { $0.version.contains("header-anchor") })
        // One bare list per release: the shared heading pattern finds nothing here.
        #expect(log.entries.allSatisfy { $0.content.isEmpty })
    }

    /// The intl page's shape since #913: no date on the newest headings, and each
    /// release split into `<p>[Label]</p><ul>…</ul>` runs. Every list in the run
    /// belongs to the release, in order, with its label as a heading.
    @Test func readsTheEnglishEntries() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: aiFixture, using: try Self.recipe(Self.intlID)))
        #expect(log.entries.map(\.version) == ["5.5.0", "5.2.7"])
        let first = try #require(log.entries.first)
        #expect(first.date == nil)
        #expect(first.items.count == 8)
        #expect(first.items.first == "Invite-a-friend credit rewards")
        #expect(first.items.last == "Profile and persona name settings")
        let older = try #require(log.entries.last)
        #expect(older.date == "2026-07-17")
        #expect(older.content == [
            .heading("Improved"),
            .note("General user experience improvements"),
            .heading("Fixed"),
            .note("General bug fixes"),
        ])
        // The label is a heading, never a change line.
        #expect(!log.entries.contains { $0.items.contains { $0.contains("[") } })
    }

    /// The trap that reading the page in a browser cannot reveal: most of the CN
    /// page's date parentheses are FULLWIDTH（）(some older ones are ASCII), the
    /// intl page's are ASCII. A pattern written for one form silently drops dates
    /// on both sites.
    @Test func theDateParenthesesDifferBetweenTheSites() throws {
        #expect(cnFixture.contains("（2026-08-17）"))
        #expect(!cnFixture.contains("(2026-08-17)"))
        #expect(aiFixture.contains("(2026-07-17)"))
        #expect(!aiFixture.contains("（2026-07-17）"))
    }

    /// 19 of the Chinese page's older entries print no date at all. The date group
    /// is optional so those still become entries rather than vanishing.
    @Test func anEntryWithNoDateStillParses() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: noDateFixture, using: try Self.recipe(Self.cnID)))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "4.24.1")
        #expect(entry.date == nil)
        #expect(!entry.items.isEmpty)
    }

    /// `</h2>\s*<ul>` adjacency is what stops a heading whose notes are laid out
    /// some other way from swallowing the NEXT release's list and filing it under
    /// the wrong version. Here 9.9.9 has no list of its own; it must be skipped
    /// entirely rather than adopting 5.3.14's items.
    @Test func aHeadingWithNoListDoesNotAdoptTheNextReleasesItems() throws {
        let doc = #"<h2 id="_9-9-9">9.9.9 版本发布 🚀（2026-09-01）</h2><p>coming soon</p>"# + cnFixture
        let log = try #require(
            ChangelogExtractor.extract(from: doc, using: try Self.recipe(Self.cnID)))
        #expect(!log.entries.contains { $0.version == "9.9.9" })
        #expect(log.entries.first?.version == "5.3.14")
    }

    /// The same guard for the labelled shape: a category label with no list
    /// after it is not the start of a run, so 9.9.9 must not reach across into
    /// 5.5.0's lists either.
    @Test func aLabelWithNoListDoesNotAdoptTheNextReleasesItems() throws {
        let doc = #"<h2 id="_9-9-9">9.9.9</h2><p>[New]</p>"# + aiFixture
        let log = try #require(
            ChangelogExtractor.extract(from: doc, using: try Self.recipe(Self.intlID)))
        #expect(log.entries.map(\.version) == ["5.5.0", "5.2.7"])
    }
}

private let cnFixture = #"""
<h2 id="_5-3-14-版本发布-🚀-2026-08-17" tabindex="-1">5.3.14 版本发布 🚀（2026-08-17） <a class="header-anchor" href="#_5-3-14-版本发布-🚀-2026-08-17" aria-label="Permalink to &quot;5.3.14 版本发布 🚀（2026-08-17）&quot;">​</a></h2><ul><li>新增 Markdown AI 编辑快捷键提示，支持 Enter 直接发送、Cmd+Enter 换行</li><li>优化长期记忆加载与本地助理变量恢复，新建和恢复对话更稳定</li><li>优化自动化任务高峰期调度，减少集中触发和误判错过执行</li><li>优化灵感案例访问和做同款流程，提升资源打开、分享口令和覆盖确认体验</li><li>优化并行灵感任务页面性能，减少任务切换卡顿和历史任务白屏</li><li>修复多个任务同时提问时回复内容串话的问题</li><li>修复技能名称为纯数字时新建会话失败的问题</li><li>修复粘贴腾讯文档链接后点击「去授权」无响应的问题</li><li>修复文件分享持续失败的问题</li><li>修复思考过程代码块重叠显示的问题</li><li>修复海外版提示词增强、历史日期和关于页跳转异常的问题</li><li>修复子 Agent 沙箱任务可能永久等待的问题</li><li>修复 Wedata 图表卡片无法正常渲染的问题</li><li>修复元宝搜索入口异常隐藏的问题</li></ul><h2 id="_5-3-13-版本发布-🚀-2026-08-13" tabindex="-1">5.3.13 版本发布 🚀（2026-08-13） <a class="header-anchor" href="#_5-3-13-版本发布-🚀-2026-08-13" aria-label="Permalink to &quot;5.3.13 版本发布 🚀（2026-08-13）&quot;">​</a></h2><ul><li>新增灵感「一键做同款」，支持快速套版复刻网页</li><li>优化同时运行多个任务时的流畅度，减少切换卡顿和白屏</li><li>优化资料库上传体验，成功后可一键跳转查看，已在资料库中的文件不再重复上传</li><li>修复子任务一直停在准备中、无法继续执行的问题</li><li>修复对话中 WeData 图表无法展示的问题</li><li>修复思考过程中代码块文字重叠的问题</li><li>修复网页搜索结果出现空链接的问题</li><li>修复分享文件弹窗遮罩样式异常的问题</li><li>修复对话区元宝搜索入口消失的问题</li><li>修复海外版提示词增强不可用的问题</li><li>修复海外版历史消息日期未按语言显示的问题</li><li>修复海外版关于页官网跳转错误的问题</li></ul>
"""#

private let aiFixture = #"""
<h2 id="_5-5-0" tabindex="-1">5.5.0 <a class="header-anchor" href="#_5-5-0" aria-label="Permalink to “5.5.0”">​</a></h2><p>[New]</p><ul><li>Invite-a-friend credit rewards</li><li>New language support (Brazilian Portuguese, Indonesian, Traditional Chinese)</li><li>IM integrations (Discord, Telegram, Slack)</li><li>Discord community entry in feedback</li></ul><p>[Fixed]</p><ul><li>Expert package downloads in overseas regions</li><li>Conversation status occasionally reverting to an earlier state</li><li>Session and task state refresh after account switching</li><li>Profile and persona name settings</li></ul><h2 id="_5-2-7-2026-07-17" tabindex="-1">5.2.7 (2026-07-17) <a class="header-anchor" href="#_5-2-7-2026-07-17" aria-label="Permalink to “5.2.7 (2026-07-17)”">​</a></h2><p>[Improved]</p><ul><li>General user experience improvements</li></ul><p>[Fixed]</p><ul><li>General bug fixes</li></ul>
"""#

private let noDateFixture = #"""
<h2 id="_4-24-1-版本发布-🚀" tabindex="-1">4.24.1 版本发布 🚀 <a class="header-anchor" href="#_4-24-1-版本发布-🚀" aria-label="Permalink to &quot;4.24.1 版本发布 🚀&quot;">​</a></h2><ul><li>优化「我分享的任务」列表，移除分享次数列并修正入口文案</li><li>优化自动化任务删除流程，减少不必要的审批确认</li><li>优化专家团协作任务调度，降低多子任务并发导致响应变慢或失控的概率</li><li>优化沙箱低风险路径识别，减少 Windows 应用安装和诊断目录操作被误拦截</li><li>优化文件读取循环检测阈值，降低正常读取大文件时被误中断的概率</li><li>修复企业微信开关关闭再开启后，消息推送可能被误拒的问题</li><li>修复 macOS 图形界面启动时语言环境为空，导致部分命令或中文内容处理异常的问题</li></ul>
"""#
