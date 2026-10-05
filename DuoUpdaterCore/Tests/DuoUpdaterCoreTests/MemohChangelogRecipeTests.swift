import Testing
import Foundation
@testable import DuoUpdaterCore

/// Memoh Desktop's notes are `felinics/Memoh`'s GitHub releases, numbered in the
/// OSS namespace (`v0.20.0`) while the app is numbered by date (`2026.9.27-1`).
/// See the recipe comment in `ai-memoh-desktop.swift` for why the two can't be
/// joined and why the entry keeps its `v`.
///
/// The fixture is three real releases from the live `per_page=20` page fetched
/// 2026-10-05. Tags, `prerelease`, `draft` and `published_at` are verbatim; the
/// v0.20.0 body keeps its real markup (the `&nbsp;`-padded `###` headings, a
/// scoped `- **agent**:` group with nested bullets, the `#####` compare footer)
/// with each list cut to its first item or two.
private let memohReleasesFixture = #"""
[
  {
    "tag_name": "v0.20.0",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-09-15T11:49:55Z",
    "body": "### &nbsp;&nbsp;&nbsp;🚀 Features\n\n- Session 模型/推理强度对持久化 &nbsp;-&nbsp; by @qqqqqf-q in https://github.com/felinics/Memoh/issues/879 and https://github.com/felinics/Memoh/issues/1139 [<samp>(25c64)</samp>](https://github.com/felinics/Memoh/commit/25c6447ce)\n- **desktop**:\n  - 后台自动更新与侧栏更新入口 &nbsp;-&nbsp; by @qqqqqf-q in https://github.com/felinics/Memoh/issues/1227 [<samp>(43154)</samp>](https://github.com/felinics/Memoh/commit/43154a570)\n\n### &nbsp;&nbsp;&nbsp;🐞 Bug Fixes\n\n- 去掉 exec 工具行悬停时的整段命令 tooltip &nbsp;-&nbsp; by @qqqqqf-q in https://github.com/felinics/Memoh/issues/1133 [<samp>(a580d)</samp>](https://github.com/felinics/Memoh/commit/a580d33d6)\n\n##### &nbsp;&nbsp;&nbsp;&nbsp;[View changes on GitHub](https://github.com/felinics/Memoh/compare/v0.19.0...v0.20.0)"
  },
  {
    "tag_name": "v0.10.0-alpha.1",
    "prerelease": true,
    "draft": false,
    "published_at": "2026-05-29T21:13:42Z",
    "body": "### &nbsp;&nbsp;&nbsp;🚀 Features\n\n- Add workspace people management &nbsp;-&nbsp; by @akazwz in https://github.com/memohai/Memoh/issues/519 [<samp>(665de)</samp>](https://github.com/memohai/Memoh/commit/665ded3b)"
  },
  {
    "tag_name": "v0.19.0",
    "prerelease": false,
    "draft": false,
    "published_at": "2026-08-30T07:47:53Z",
    "body": "### &nbsp;&nbsp;&nbsp;🚀 Features\n\n- Provider 连接测试增加「无法确认」中间态,不再对无 models 端点误判失败 &nbsp;-&nbsp; by @qqqqqf-q in https://github.com/felinics/Memoh/issues/1088 [<samp>(4add8)</samp>](https://github.com/felinics/Memoh/commit/4add859a)"
  }
]
"""#

private func memohChangelogRecipe() throws -> ChangelogRecipe {
    try #require(
        ChangelogRecipeRegistry.recipes.first { $0.bundleID == "ai.memoh.desktop" },
        "no Memoh changelog recipe")
}

private func decoded() throws -> Changelog {
    try #require(ChangelogService.parse(try memohChangelogRecipe(), body: memohReleasesFixture))
}

/// The rail is stable releases only, each under its tag as GitHub spells it.
@Test func memohChangelogKeepsTheTagAndDropsPrereleases() throws {
    #expect(try decoded().entries.map(\.version) == ["v0.20.0", "v0.19.0"])
}

/// The `v` is load-bearing, not cosmetic. Without it the entry is version-shaped,
/// and every OSS release reads as "a whole release behind" the date-numbered app.
/// This pins the recipe side; `BaselineTests` pins that the `v` keeps `duo
/// verify`'s lag check out of it.
@Test func memohChangelogEntriesAreNotPlainVersionNumbers() throws {
    for entry in try decoded().entries {
        #expect(entry.version.first?.isNumber == false, "\(entry.version) would be compared to 2026.x")
    }
}

/// The real body's section headings survive (with their `&nbsp;` padding gone),
/// a scoped group folds its scope into the child item, the `by @… in …` credit
/// and commit link are trimmed, and the compare-link footer is not an item.
@Test func memohReleaseBodyKeepsItsSections() throws {
    let newest = try #require(try decoded().entries.first)
    #expect(newest.date == "2026-09-15")
    let headings = newest.content.compactMap { block -> String? in
        if case .heading(let h) = block { return h }
        return nil
    }
    #expect(headings == ["🚀 Features", "🐞 Bug Fixes"])
    #expect(newest.items == [
        "Session 模型/推理强度对持久化",
        "**desktop**: 后台自动更新与侧栏更新入口",
        "去掉 exec 工具行悬停时的整段命令 tooltip",
    ])
}
