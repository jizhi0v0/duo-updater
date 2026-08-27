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
/// Fixtures are verbatim slices of the live pages, fetched 2026-08-27.
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
    }

    @Test func readsTheEnglishEntries() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: aiFixture, using: try Self.recipe(Self.intlID)))
        #expect(log.entries.count == 2)
        let first = try #require(log.entries.first)
        // "Lanched" is the vendor's own typo; the pattern must not depend on the
        // word at all, which is what lets it also read "版本发布" and the bare form.
        #expect(first.version == "5.2.7")
        #expect(first.date == "2026-07-17")
        #expect(first.items == ["Bug fixes and user experience improvements."])
        #expect(log.entries.last?.version == "5.2.3")
        #expect(log.entries.last?.items.count == 10)
    }

    /// The trap that reading the page in a browser cannot reveal: the parentheses
    /// around every date are FULLWIDTH（）on both sites. A pattern written with
    /// `\(` matches neither page, and the failure looks like "the vendor changed
    /// their layout" rather than "we typed the wrong bracket".
    @Test func theDateParenthesesAreFullwidthOnBothSites() throws {
        #expect(cnFixture.contains("（2026-08-17）"))
        #expect(aiFixture.contains("（2026-07-17）"))
        #expect(!cnFixture.contains("(2026-08-17)"))
        #expect(!aiFixture.contains("(2026-07-17)"))
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
}

private let cnFixture = #"""
<h2 id="_5-3-14-版本发布-🚀-2026-08-17" tabindex="-1">5.3.14 版本发布 🚀（2026-08-17） <a class="header-anchor" href="#_5-3-14-版本发布-🚀-2026-08-17" aria-label="Permalink to &quot;5.3.14 版本发布 🚀（2026-08-17）&quot;">​</a></h2><ul><li>新增 Markdown AI 编辑快捷键提示，支持 Enter 直接发送、Cmd+Enter 换行</li><li>优化长期记忆加载与本地助理变量恢复，新建和恢复对话更稳定</li><li>优化自动化任务高峰期调度，减少集中触发和误判错过执行</li><li>优化灵感案例访问和做同款流程，提升资源打开、分享口令和覆盖确认体验</li><li>优化并行灵感任务页面性能，减少任务切换卡顿和历史任务白屏</li><li>修复多个任务同时提问时回复内容串话的问题</li><li>修复技能名称为纯数字时新建会话失败的问题</li><li>修复粘贴腾讯文档链接后点击「去授权」无响应的问题</li><li>修复文件分享持续失败的问题</li><li>修复思考过程代码块重叠显示的问题</li><li>修复海外版提示词增强、历史日期和关于页跳转异常的问题</li><li>修复子 Agent 沙箱任务可能永久等待的问题</li><li>修复 Wedata 图表卡片无法正常渲染的问题</li><li>修复元宝搜索入口异常隐藏的问题</li></ul><h2 id="_5-3-13-版本发布-🚀-2026-08-13" tabindex="-1">5.3.13 版本发布 🚀（2026-08-13） <a class="header-anchor" href="#_5-3-13-版本发布-🚀-2026-08-13" aria-label="Permalink to &quot;5.3.13 版本发布 🚀（2026-08-13）&quot;">​</a></h2><ul><li>新增灵感「一键做同款」，支持快速套版复刻网页</li><li>优化同时运行多个任务时的流畅度，减少切换卡顿和白屏</li><li>优化资料库上传体验，成功后可一键跳转查看，已在资料库中的文件不再重复上传</li><li>修复子任务一直停在准备中、无法继续执行的问题</li><li>修复对话中 WeData 图表无法展示的问题</li><li>修复思考过程中代码块文字重叠的问题</li><li>修复网页搜索结果出现空链接的问题</li><li>修复分享文件弹窗遮罩样式异常的问题</li><li>修复对话区元宝搜索入口消失的问题</li><li>修复海外版提示词增强不可用的问题</li><li>修复海外版历史消息日期未按语言显示的问题</li><li>修复海外版关于页官网跳转错误的问题</li></ul>
"""#

private let aiFixture = #"""
<h2 id="_5-2-7-lanched-🚀-2026-07-17" tabindex="-1">5.2.7 Lanched 🚀（2026-07-17） <a class="header-anchor" href="#_5-2-7-lanched-🚀-2026-07-17" aria-label="Permalink to &quot;5.2.7 Lanched 🚀（2026-07-17）&quot;">​</a></h2><ul><li>Bug fixes and user experience improvements.</li></ul><h2 id="_5-2-3-lanched-🚀-2026-07-15" tabindex="-1">5.2.3 Lanched 🚀（2026-07-15） <a class="header-anchor" href="#_5-2-3-lanched-🚀-2026-07-15" aria-label="Permalink to &quot;5.2.3 Lanched 🚀（2026-07-15）&quot;">​</a></h2><ul><li>Added sharing support for tasks and outputs, allowing users to generate a link with one click and share it with friends.</li><li>Improved the chat input toolbar in compact mode and restored input height after sending messages for a steadier small-window experience.</li><li>Fixed conversation recovery after weak-network disconnections so the next prompt can continue correctly.</li><li>Fixed Claw multi-device messaging issues and MCP session recovery after session loss.</li><li>Fixed false connector failure prompts and duplicate connected notifications during quick switching or reconnection.</li><li>Fixed missing tool-call displays after switching project tasks and flickering in-progress task filters.</li><li>Fixed custom expert and expert-team member mapping issues, default prompt errors, and invalid configurations that could cause exceptions.</li><li>Fixed duplicated streaming content, message grouping issues, and incorrect cancellation-state display.</li><li>Fixed Windows issues where opening files from results could fail and Add Expert/Skill popovers could become unresponsive.</li><li>Fixed upgrade and renewal buttons in international builds by opening them in the external browser to avoid blocked pop-ups.</li></ul>
"""#

private let noDateFixture = #"""
<h2 id="_4-24-1-版本发布-🚀" tabindex="-1">4.24.1 版本发布 🚀 <a class="header-anchor" href="#_4-24-1-版本发布-🚀" aria-label="Permalink to &quot;4.24.1 版本发布 🚀&quot;">​</a></h2><ul><li>优化「我分享的任务」列表，移除分享次数列并修正入口文案</li><li>优化自动化任务删除流程，减少不必要的审批确认</li><li>优化专家团协作任务调度，降低多子任务并发导致响应变慢或失控的概率</li><li>优化沙箱低风险路径识别，减少 Windows 应用安装和诊断目录操作被误拦截</li><li>优化文件读取循环检测阈值，降低正常读取大文件时被误中断的概率</li><li>修复企业微信开关关闭再开启后，消息推送可能被误拒的问题</li><li>修复 macOS 图形界面启动时语言环境为空，导致部分命令或中文内容处理异常的问题</li></ul>
"""#
