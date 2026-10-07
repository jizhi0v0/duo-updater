import Foundation
import Testing

@testable import DuoUpdaterCore

/// Cindy's notes (`com_xd_cindy.changelog(for:)`, shared by both editions).
///
/// Fixture: four real releases from `makecindy/cindy` (fetched 2026-10-07), in
/// API field order, trimmed — 0.1.97 to two of its sections and two PR links;
/// 0.1.20 to two bullets per section — with `v1.0.0` put first, where it would
/// sit if it were the newest row.
@Suite struct CindyChangelogRecipeTests {

    @Test(arguments: ["com.xd.cindy", "com.xd.cindycn"])
    func eachSectionIsOneChangeUnderItsHeading(_ bundleID: String) throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID))
        let changelog = try #require(ChangelogExtractor.extract(from: cindyReleasesFixture, using: recipe))

        // No 1.0.0 snapshot, no 0.1.96 beta.
        #expect(changelog.entries.map(\.version) == ["0.1.97", "0.1.20"])
        let newest = try #require(changelog.entries.first)
        #expect(newest.date == "2026-10-03")
        #expect(newest.items.count == 2)
        #expect(newest.items.first?.hasPrefix("可以在 Cindy 里直接安装 llama.cpp 运行环境") == true)
        #expect(newest.items.last?.hasSuffix("@DavidShenXD") == true)
        #expect(newest.content == [
            .heading("🧠 本机模型"), .note(newest.items[0]),
            .heading("🖼️ 桌面壁纸"), .note(newest.items[1]),
        ])
        // The PR links and the build metadata after `---` are not changes.
        #expect(!newest.items.contains { $0.contains("commit:") || $0.contains("pull/") })

        // The one shape that lists its changes: bullets, not the first line only.
        let bullets = try #require(changelog.entries.last)
        #expect(bullets.items.count == 4)
        #expect(bullets.items.first?.hasPrefix("出站代理新增 SOCKS5 支持") == true)
        #expect(!bullets.items.contains { $0.contains("source tag") })
    }

    /// A release that mixes the two shapes keeps both, in order. Not a shape
    /// the vendor has published (every real body is one or the other); it is
    /// the case a first-wins pair of item patterns would get wrong — the one
    /// bullet would win and every paragraph would vanish. Mutation (run): the
    /// two-pattern form keeps only the bullets here.
    @Test func aBulletInAParagraphBodyDoesNotDropTheParagraphs() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.xd.cindy"))
        let json = #"""
        [{"tag_name":"v0.1.98","name":"v0.1.98","draft":false,"prerelease":false,"created_at":"2026-10-08T01:00:00Z","published_at":"2026-10-08T02:00:00Z","body":"Desktop release 0.1.98\n\n## 更新说明\n### 🧠 本机模型\n第一段。 @a\n\n### 🛠️ 修复\n- 第一条修复\n- 第二条修复\n\n### 🖼️ 桌面壁纸\n第三段。 @b\n\n## PRs\n[#1](https://github.com/makecindy/cindy/pull/1)\n\n---\n- commit: `abc`\n"}]
        """#
        let changelog = try #require(ChangelogExtractor.extract(from: json, using: recipe))
        let entry = try #require(changelog.entries.first)
        #expect(entry.items == ["第一段。 @a", "第一条修复", "第二条修复", "第三段。 @b"])
        #expect(entry.content == [
            .heading("🧠 本机模型"), .note("第一段。 @a"),
            .heading("🛠️ 修复"), .note("第一条修复"), .note("第二条修复"),
            .heading("🖼️ 桌面壁纸"), .note("第三段。 @b"),
        ])
    }
}

private let cindyReleasesFixture = #"""
[{"tag_name":"v1.0.0","name":"Cindy 1.0.0","draft":false,"prerelease":false,"created_at":"2026-07-25T07:45:47Z","published_at":"2026-07-25T07:47:06Z","body":"想到，就能做到。 / Consider it done.\n\n## 下载 / Download\n\n- Download：https://cindy.app/download/\n- 中国大陆版 / Mainland China edition：https://cindy.cn/download/\n\n官方安装包由官网与官方 CDN 分发并自动更新；本 Release 标记 1.0.0 版本期的开源客户端源码快照。\n\nOfficial installers are distributed and auto-updated through the official sites and CDN; this release marks the open-source client source snapshot for the 1.0.0 line.\n"},
{"tag_name":"v0.1.97","name":"v0.1.97","draft":false,"prerelease":false,"created_at":"2026-10-03T01:26:01Z","published_at":"2026-10-03T16:20:12Z","body":"Desktop release 0.1.97\n\n## 更新说明\n### 🧠 本机模型\n可以在 Cindy 里直接安装 llama.cpp 运行环境并下载模型，首次使用自动启动，下载可暂停、继续与取消；Flash-Next 默认 256K 上下文，可开到 100 万 tokens。 @dashhuang\n\n### 🖼️ 桌面壁纸\n设置里新增壁纸：内置三款 Cindy 插画场景，每款可选静态或动态，动态画面已随客户端内置、断网也能播放；也可以用自己的图片，并调节蒙层深浅保证文字清晰。 @DavidShenXD\n\n## PRs\n[#4432](https://github.com/makecindy/cindy/pull/4432) [#5110](https://github.com/makecindy/cindy/pull/5110)\n\n---\n- commit: `88e224475a6183f7b31218a7499be956a4bf2667`\n- source tag: `beta2026-10-03_23-39-47`\n- regions: cn global\n- iOS(cn):整包 0.1.10(2026092401) · 热更 (无热更)\n- Android(cn):整包 0.1.20(32) · 热更 (无热更)\n- iOS(global):整包 0.1.10(2026092401) · 热更 cb56b985\n- Android(global):整包 0.1.20(26) · 热更 (无热更)\n"},
{"tag_name":"v0.1.96-beta","name":"v0.1.96-beta","draft":false,"prerelease":true,"created_at":"2026-09-29T15:23:56Z","published_at":"2026-09-30T02:58:59Z","body":"Desktop release 0.1.96\n\n## 更新说明\n### 🧩 伙伴导入更完整\n从 Hermes、OpenClaw 导入伙伴时，Skill、记忆和自动化定义不再遗漏，默认全选并可按分类搜索。缺少投放渠道的任务不再丢失，会保留配置并显示为停用任务；保存不全时会给出数量和重试入口。 @zqchris\n\n## PRs\n[#3024](https://github.com/makecindy/cindy/pull/3024) [#5110](https://github.com/makecindy/cindy/pull/5110)\n\n---\n- commit: `f7f265ef2e4316d37a7ce6d4e03006a826e397e4`\n- source tag: `beta2026-09-30_10-47-43`\n- regions: cn global\n- iOS(cn):整包 0.1.10(2026092401) · 热更 (无热更)\n- Android(cn):整包 0.1.20(32) · 热更 (无热更)\n- iOS(global):整包 0.1.10(2026092401) · 热更 cb56b985\n- Android(global):整包 0.1.20(26) · 热更 (无热更)\n"},
{"tag_name":"v0.1.20","name":"v0.1.20","draft":false,"prerelease":false,"created_at":"2026-07-28T01:27:58Z","published_at":"2026-07-28T04:36:08Z","body":"Desktop release 0.1.20\n\n## 更新说明\n### New Features\n- 出站代理新增 SOCKS5 支持——代理软件只开 SOCKS 出口时不再全部直连失败 @dashhuang\n- 语音词典在同账号设备之间自动同步——桌面端之间对等收敛,手机端可查看并使用电脑上的词典 @dashhuang\n### Bug Fixes\n- 修复代理环境下 Claude 授权交换 token 时 403——出站代理现已覆盖所有主进程出网请求 @dashhuang\n- 修复 xAI 订阅 OAuth 被上游作废后无限 403 且设置仍显示已连接——现在会自动刷新或引导重连 @dashhuang\n\n---\n- commit: `e13b4e76be95f28080490d6a617f79e769fdf447`\n- source tag: `release2026-07-28_12-22-04`\n- regions: cn global\n"}]
"""#
