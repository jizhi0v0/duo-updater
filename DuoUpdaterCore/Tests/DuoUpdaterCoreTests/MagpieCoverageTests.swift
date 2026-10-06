import Testing
import Foundation
@testable import DuoUpdaterCore

/// magpie (`com.yetone.magpie`): a GitHub rule on `yetone/magpie-releases` and
/// a `.gitHubReleases` changelog recipe over the same bodies. What is pinned:
/// the rule picks the right zip per architecture, and the notes come out as the
/// English changes alone — the bodies also carry download boilerplate and a
/// full Chinese translation under the same headings.
///
/// See `docs/app-audits/com-yetone-magpie.md` for the measurements.
@Suite struct MagpieCoverageTests {

    /// v0.1.1084's release object as GitHub served it (2026-10-06), trimmed to
    /// the fields the decoder reads.
    static let releasesFixture = #"""
[
 {
  "tag_name": "v0.1.1084",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-10-06T10:33:23Z",
  "html_url": "https://github.com/yetone/magpie-releases/releases/tag/v0.1.1084",
  "body": "## Features\n- Added reasoning effort selection for Cursor Private Inference, with sensible defaults and precedence over existing routing settings.\n- The GUI can now discover local provider configurations and supports permanently dismissing discovered items.\n\n## Bug Fixes\n- Fixed the menu bar icon opening the Allowances tab every time; it now opens the last-used tab.\n- Fixed a wrong 404 response when clients attempted a WebSocket connection to the Responses endpoint; magpie now tells them to use HTTP/SSE instead.\n- Fixed Azure OpenAI/OpenAI errors caused by magpie-generated reasoning items, and made summary/compaction retry as plain text when an item is reported as missing.\n- Fixed web search requests being sent to Chat instead of the provider API that actually serves the client's model.\n- Fixed a hang when Claude Code sent a long reply before the request started reading it.\n\n## Improvements\n- ZCode integration now detects ZCode gift plans that still need to be claimed in the ZCode app, so routing and caps handle them correctly instead of failing.\n\n### Install\n\nDownload from [usemagpie.ai](https://usemagpie.ai), or `curl -fsSL https://usemagpie.ai/install.sh | sh`. An installed magpie updates itself.\n\n- **macOS (Apple Silicon):** `magpie-darwin-arm64.dmg`\n- **macOS (Intel):** `magpie-darwin-amd64.dmg`\n- **Windows:** `magpie-windows-amd64.exe` (ARM: `magpie-windows-arm64.exe`)\n- **Linux:** `magpie-linux-amd64` / `magpie-linux-arm64` (needs GTK 3 and WebKitGTK 4.1)\n- **Terminal only:** `magpie-cli-<os>-<arch>`\n\n<!-- lang:zh -->\n\n## Features\n- 为 Cursor Private Inference 添加了推理强度选择，提供合理默认值，并优先于现有路由设置。\n- GUI 现在可以发现本地提供商配置，并支持永久忽略已发现的项目。\n\n## Bug Fixes\n- 修复了菜单栏图标每次打开“配额”标签页的问题；现在会打开上次使用的标签页。\n- 修复了客户端尝试通过 WebSocket 连接 Responses 端点时返回错误 404 的问题；magpie 现在会提示改用 HTTP/SSE。\n- 修复了由 magpie 生成的推理项导致的 Azure OpenAI/OpenAI 错误，并在某个项被报告为缺失时，使摘要/压缩以纯文本方式重试。\n- 修复了网络搜索请求被发送到 Chat 而不是实际服务于客户端模型的提供商 API 的问题。\n- 修复了 Claude Code 在请求开始读取之前发送长回复时导致挂起的问题。\n\n## Improvements\n- ZCode 集成现在可以检测仍需在 ZCode 应用中领取的 ZCode 礼品计划，从而使路由和额度限制能够正确处理，而不是失败。\n\n### 安装\n\n从 [usemagpie.ai](https://usemagpie.ai) 下载，或运行 `curl -fsSL https://usemagpie.ai/install.sh | sh`。已安装的 magpie 会自动更新。\n"
 }
]
"""#

    private static var rule: GitHubReleaseRule {
        get throws {
            let found = GitHubReleaseRegistry.rules.filter { $0.bundleID == "com.yetone.magpie" }
            try #require(found.count == 1, "com.yetone.magpie should have exactly one GitHub rule")
            return found[0]
        }
    }

    private static var recipe: ChangelogRecipe {
        get throws {
            try #require(
                ChangelogRecipeRegistry.recipe(
                    forBundleID: "com.yetone.magpie", channel: .stable, version: "0.1.1084"),
                "com.yetone.magpie has no changelog recipe")
        }
    }

    @Test(arguments: [
        ("v0.1.1084", "0.1.1084"),
        ("v0.1.983", "0.1.983"),
        ("0.1.1084", nil),
        ("v0.1.1084-rc1", nil),
    ])
    func tagsResolveToTheBundleVersion(tag: String, expected: String?) throws {
        #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: try Self.rule.versionPattern)
                == expected)
    }

    /// Every macOS-looking asset v0.1.1084 published. Only the two zips are
    /// installable — the dmgs hold the same bundle but the zip is what the app's
    /// own updater and install.sh use — and the CLI binaries are no bundle.
    static let realAssetNames = [
        "magpie-cli-darwin-amd64", "magpie-cli-darwin-arm64",
        "magpie-darwin-amd64.dmg", "magpie-darwin-amd64.zip",
        "magpie-darwin-arm64.dmg", "magpie-darwin-arm64.zip",
        "magpie-linux-arm64", "magpie-windows-arm64.exe", "SHA256SUMS",
    ]

    @Test(arguments: [(HostArch.arm64, "magpie-darwin-arm64.zip"),
                      (HostArch.x86_64, "magpie-darwin-amd64.zip")])
    func eachArchitectureGetsItsOwnZip(arch: HostArch, expected: String) throws {
        let assets: [(name: String, url: URL, size: Int64?)] = Self.realAssetNames.map {
            (name: $0,
             url: URL(string: "https://github.com/yetone/magpie-releases/releases/download/v0.1.1084/\($0)")!,
             size: nil)
        }
        let rule = try Self.rule
        let pattern = try #require(rule.installAssetPattern)
        let chosen = GitHubReleaseRule.installableAsset(
            from: assets, matching: pattern, preferring: arch, allowingIntelTranslation: false)
        #expect(chosen?.url.lastPathComponent == expected)
    }

    /// The real body parses to its eight English changes under their three
    /// headings: no "Install" bullets, no second copy in Chinese.
    @Test func notesAreTheEnglishChangesOnly() throws {
        let r = try Self.recipe
        let format = try #require(r.structuredFormat)
        let changelog = try #require(StructuredChangelogDecoder.decode(
            Self.releasesFixture, format: format, channel: r.channel,
            maxEntries: r.maxEntries, skipSections: r.skipSections))
        let entry = try #require(changelog.entries.first)
        #expect(changelog.entries.map(\.version) == ["0.1.1084"])
        #expect(entry.items.count == 8)
        let headings = entry.content.compactMap { block -> String? in
            if case .heading(let h) = block { return h }
            return nil
        }
        #expect(headings == ["Features", "Bug Fixes", "Improvements"])
        #expect(!entry.items.contains { $0.contains("magpie-darwin-arm64.dmg") })
        #expect(!entry.items.contains { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } })
    }

    /// The two halves of that, each shown to matter on the same body. Below the
    /// marker is a second complete changelog under the SAME headings — which is
    /// why no `skipSections` entry could drop it and the parser cuts it instead
    /// (before the cut this body parsed to 21 items). Above it, the parser alone
    /// still keeps the five download bullets the recipe's skip removes.
    @Test func bothCutsAreLoadBearing() throws {
        let releases = try JSONSerialization.jsonObject(with: Data(Self.releasesFixture.utf8))
        let body = try #require((releases as? [[String: Any]])?.first?["body"] as? String)
        let english = GitHubMarkdownParser.firstLanguage(of: body)
        let translation = String(body.dropFirst(english.count))
        #expect(translation.hasPrefix("<!-- lang:zh -->"))

        let copy = try #require(GitHubMarkdownParser.parse(
            body: String(translation.drop { $0 != "\n" }), version: "0.1.1084", date: nil))
        #expect(copy.entries[0].items.count == 8)
        #expect(copy.entries[0].content.compactMap { block -> String? in
            if case .heading(let h) = block { return h }
            return nil
        } == ["Features", "Bug Fixes", "Improvements"])

        let noSkip = try #require(GitHubMarkdownParser.parse(body: body, version: "0.1.1084", date: nil))
        #expect(noSkip.entries[0].items.count == 13)
    }

    @Test func aBodyWithoutTheMarkerIsUntouched() {
        let body = "## Fixes\n- one <!-- lang:zh --> inline\n- two\n"
        #expect(GitHubMarkdownParser.firstLanguage(of: body) == body)
    }
}
