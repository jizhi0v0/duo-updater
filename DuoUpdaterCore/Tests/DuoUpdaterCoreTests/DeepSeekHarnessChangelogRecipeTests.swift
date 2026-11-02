import Testing
import Foundation
@testable import DuoUpdaterCore

/// DeepSeek Harness (official) — `com.deepseek.dsh`, the 0.2.x desktop client.
///
/// Trimmed slices of `api.github.com/repos/deepseek-ai/deepseek-harness/releases`
/// (fetched 2026-11-02): the two newest `-rc.N` builds — one written with raw
/// `<h3>` headings, one mixing them with `###` — plus the parallel `-alpha.N`
/// train, cut down to its first Chinese and first English section. The alpha
/// entry must not reach the pane.
private let deepSeekHarnessReleases = #"""
[
  {
    "tag_name": "dsh-v0.2.1-rc.5",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-10-30T02:12:26Z",
    "body": "[中文](#cn-v0.2.1-rc.5-community) | [English](#en-v0.2.1-rc.5-community)\n\n<h3 id=\"cn-v0.2.1-rc.5-community\">体验优化</h3>\n\n- 优化对话中思考内容的展示效果。 @LegGasai\n\n<h3 id=\"en-v0.2.1-rc.5-community\">Improvements</h3>\n\n- Improve how thinking content is displayed in conversations. by @LegGasai\n\nFull Changelog: [dsh-v0.2.1-rc.4...dsh-v0.2.1-rc.5](https://github.com/deepseek-ai/deepseek-harness/compare/dsh-v0.2.1-rc.4...dsh-v0.2.1-rc.5)\n"
  },
  {
    "tag_name": "dsh-v0.2.1-rc.3",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-10-23T15:26:39Z",
    "body": "[中文](#cn-v0.2.1-rc.3-community) | [English](#en-v0.2.1-rc.3-community)\r\n\r\n<h3 id=\"cn-v0.2.1-rc.3-community\">体验优化</h3>\r\n\r\n- 新增左侧栏、会话视图和右侧栏的「更多」菜单，方便浏览和创建插件。 @Yifffan, @imccyu\r\n- 修复切换会话后，点击「新会话」找不回未发送草稿的问题。 @imccyu\r\n\r\n### 其他变更\r\n\r\n- DeepSeek API Key 适配器的模型列表更新方式与账号登录模式保持一致。 @LegGasai\r\n\r\n<h3 id=\"en-v0.2.1-rc.3-community\">Improvements</h3>\r\n\r\n- Add More menus to the left sidebar, conversation views, and right sidebar for browsing and creating plugins. by @Yifffan, @imccyu\r\n- Fix New Session losing an unsent draft after switching sessions. by @imccyu\r\n\r\n### Chores\r\n\r\n- The DeepSeek API key adapter now updates its model list the same way as account sign-in. by @LegGasai\r\n\r\nFull Changelog: [dsh-v0.2.1-rc.2...dsh-v0.2.1-rc.3](https://github.com/deepseek-ai/deepseek-harness/compare/dsh-v0.2.1-rc.2...dsh-v0.2.1-rc.3)"
  },
  {
    "tag_name": "dsh-v0.2.2-alpha.2",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-10-28T02:50:54Z",
    "body": "[中文](#cn-v0.2.2-alpha.2-community) | [English](#en-v0.2.2-alpha.2-community)\n\n<h3 id=\"cn-v0.2.2-alpha.2-community\">新增功能</h3>\n\n- 插件管理页支持展示富文本详情，并改善页面布局和导航行为。 @turtle1999, @turtle2099\n- 插件管理支持更新第三方插件包；热更新失败时会尝试恢复旧版本。 @turtle1999, @turtle2099\n\n<h3 id=\"en-v0.2.2-alpha.2-community\">New Features</h3>\n\n- Show rich-text plugin details in the plugin manager and improve page layout and navigation. by @turtle1999, @turtle2099\n- Support updating third-party plugin packages and attempt to restore the previous version if hot updates fail. by @turtle1999, @turtle2099"
  }
]
"""#

/// The notes come from the upstream repo, not the update feed: the Electron
/// manifest carries none, and the releases are the vendor's own bilingual notes.
@Test func deepSeekHarnessReadsTheRCTrainFromGitHubReleases() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.deepseek.dsh"),
        "DeepSeek Harness must have a changelog recipe")
    #expect(recipe.structuredFormat == .gitHubReleases)
    #expect(recipe.source.host == "api.github.com")

    let log = try #require(StructuredChangelogDecoder.decode(
        deepSeekHarnessReleases, format: .gitHubReleases, channel: recipe.channel,
        maxEntries: recipe.maxEntries, includesPromotedStable: recipe.includesPromotedStable,
        tagPattern: recipe.tagPattern))

    // The tag carries a `dsh-v` prefix the decoder cannot strip on its own, and
    // the alpha train beside it is a build no desktop install is offered.
    #expect(log.entries.map(\.version) == ["0.2.1-rc.5", "0.2.1-rc.3"])

    // Both languages are kept, Chinese first: the vendor publishes no
    // per-language body.
    let newest = try #require(log.entries.first)
    #expect(newest.date == "2026-10-30")
    #expect(newest.items == [
        "优化对话中思考内容的展示效果。 @LegGasai",
        "Improve how thinking content is displayed in conversations. by @LegGasai",
    ])
    // One body mixes raw `<h3>` with `###`; either way the bullets flatten into
    // one list and the category headings are not items.
    let second = log.entries[1]
    #expect(second.items.count == 6)
    #expect(second.items.first == "新增左侧栏、会话视图和右侧栏的「更多」菜单，方便浏览和创建插件。 @Yifffan, @imccyu")
    #expect(second.items.last == "The DeepSeek API key adapter now updates its model list the same way as account sign-in. by @LegGasai")
    #expect(!second.items.contains { $0.contains("其他变更") || $0.contains("Chores") })
}

/// The copy on disk reads as `.stable` (`0.2.1-rc.5` is not a shape
/// `ReleaseChannel.detect` knows), so the recipe is reached by the lookup's last
/// step. Pinned because that step is the only thing between this app and an
/// empty pane.
@Test func deepSeekHarnessRecipeAnswersForAStableClassifiedCopy() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.deepseek.dsh", channel: .stable))
    #expect(recipe.channel == .nightly)
}

/// The graduation contract, on a constructed array rather than vendor bytes: no
/// plain release exists yet. The line ships `0.2.1-rc.5` → `0.2.1` with no
/// renumbering, so a release GitHub stops marking `prerelease` is still this
/// app's — a prerelease-only filter would drop the build the feed then serves.
@Test func deepSeekHarnessKeepsAGraduatedRelease() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.deepseek.dsh"))
    let feed = #"""
    [{"tag_name":"dsh-v0.2.1","prerelease":false,"draft":false,
      "published_at":"2026-11-05T00:00:00Z","body":"- 正式发布。 @LegGasai"},
     {"tag_name":"dsh-v0.2.2-alpha.2","prerelease":true,"draft":false,
      "published_at":"2026-11-06T00:00:00Z","body":"- Alpha 轨。 @LegGasai"}]
    """#
    let log = try #require(StructuredChangelogDecoder.decode(
        feed, format: .gitHubReleases, channel: recipe.channel,
        maxEntries: recipe.maxEntries, includesPromotedStable: recipe.includesPromotedStable,
        tagPattern: recipe.tagPattern))
    #expect(log.entries.map(\.version) == ["0.2.1"])
}
