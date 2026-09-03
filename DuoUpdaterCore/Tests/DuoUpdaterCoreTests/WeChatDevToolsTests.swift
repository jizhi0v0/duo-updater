import Testing
import Foundation
@testable import DuoUpdaterCore

// MARK: - fixtures

/// Trimmed from the real `devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/
/// config.json`, captured 2026-08-18. Descriptions and the Windows/x64 downloads are
/// cut; everything the recipes read is verbatim, INCLUDING the two traps:
///   - the three channels sit in ONE document, in `stable, rc, nightly` order, so a
///     pattern that isn't anchored on its own `"id"` reads whichever comes first;
///   - a fourth entry, `"nightly-old"` (the retired NW.js 2.01 train), whose id has
///     `nightly` as a PREFIX and whose version is much lower.
private let wechatDevToolsConfigFixture = """
{
  "wechat_style_primary_color": "#07C160",
  "channels": [
    {
      "id": "stable",
      "name": "稳定版 Stable Build",
      "version": "2.02.2608040",
      "date": "2026-08-18",
      "history_file": "history_stable.json",
      "downloads": [
        {
          "os": "Windows",
          "arch": "64",
          "url": "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/release/be1ec64cf6184b0fa64091919793f068/wechat_devtools_2.02.2608040_win32_x64.exe"
        },
        {
          "os": "macOS",
          "arch": "x64",
          "url": "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/release/be1ec64cf6184b0fa64091919793f068/wechat_devtools_2.02.2608040_darwin_x64.pkg"
        },
        {
          "os": "macOS",
          "arch": "ARM64",
          "url": "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/release/be1ec64cf6184b0fa64091919793f068/wechat_devtools_2.02.2608040_darwin_arm64.pkg"
        }
      ]
    },
    {
      "id": "rc",
      "name": "预发布版 RC Build",
      "version": "2.02.2608031",
      "date": "2026-08-03",
      "history_file": "history_rc.json",
      "downloads": [
        {
          "os": "macOS",
          "arch": "x64",
          "url": "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/release/be1ec64cf6184b0fa64091919793f068/wechat_devtools_2.02.2608031_darwin_x64.pkg"
        },
        {
          "os": "macOS",
          "arch": "ARM64",
          "url": "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/release/be1ec64cf6184b0fa64091919793f068/wechat_devtools_2.02.2608031_darwin_arm64.pkg"
        }
      ]
    },
    {
      "id": "nightly",
      "name": "开发版 Nightly Build",
      "version": "2.02.2608182",
      "date": "2026-08-18",
      "downloads": [
        {
          "os": "macOS",
          "arch": "ARM64",
          "url": "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/electron-36.6.0/wechat_devtools_2.02.2608182_darwin_arm64.pkg"
        }
      ]
    },
    {
      "id": "nightly-old",
      "name": "开发版 Nightly Build (NW.js)",
      "version": "2.01.2602282",
      "date": "2026-02-28",
      "history_file": "history_nightly.json",
      "downloads": [
        {
          "os": "macOS",
          "arch": "ARM64",
          "url": "https://dldir1.qq.com/WechatWebDev/nightly/p-3bd19c2db3a642a0b39af853efaf67f8/0.54.1/wechat_devtools_2.01.2602282_darwin_arm64.dmg"
        }
      ]
    }
  ]
}
"""

/// The real `logs/rc_v2.02.2608031.json`, trimmed to three of its eight items.
/// The item shapes are verbatim: every line is numbered "1." (they are authored as
/// markdown lists, so the ordinal is decoration) and carries a backticked marker
/// whose vocabulary differs per channel — `修复` here, `F`/`A` on Stable/Nightly.
private let wechatDevToolsRCLogFixture = """
{
  "version": "2.02.2608031",
  "update_time": "2026-08-03",
  "tags": [{ "text": "RC Build", "color": "blue" }],
  "categories": [
    {
      "title": "🐛 问题修复",
      "tag": { "text": "Fix", "color": "blue" },
      "items": [
        "1. `修复` 切换 appid 相关反馈问题",
        "1. `修复` showToast 设置自定义图片时无法显示",
        "1. `F` 修复 第三方 AI 评测 `wx.login`"
      ]
    }
  ]
}
"""

/// The real `logs/nightly_v2.02.2609022.json`, captured 2026-09-03. Tencent
/// published the build with no categorized change lines; the per-version document
/// still carries its version, date, and Nightly description.
private let wechatDevToolsNightlyEmptyCategoriesFixture = """
{
  "version": "2.02.2609022",
  "update_time": "2026-09-02",
  "tags": [
    {
      "text": "Nightly Electron Build",
      "text_en": "Nightly Electron Build",
      "color": "red"
    }
  ],
  "desc": "日常构建版本, 2.02.2603212 开始基于 Electron 36.6(对应 Chromium 136)， 2.01.2602282 且更早之前版本是基于 NW.js 0.54.1（Chromium 93)，用于尽快修复缺陷和敏捷上线小的特性；开发自测验证，稳定性欠佳",
  "categories": []
}
"""

/// The `package.json` each build runs on, as captured from four real bundles on
/// 2026-08-18 — the installed 2.01.2510290 (NW.js, `Contents/Resources/package.nw/`)
/// and the 2.02 RC / Stable / Nightly pkg payloads (Electron,
/// `Contents/Resources/app.asar.unpacked/`). Only the fields the scanner reads are
/// kept; `versionType` is a STRING in every one of them.
private func wechatPackageJSON(
    version: String, versionType: String?, title: String, appname: String = "wechatwebdevtools"
) -> [String: Any] {
    var json: [String: Any] = [
        "name": "微信开发者工具",
        "productName": "微信开发者工具",
        "appname": appname,
        "product_string": appname,
        "version": version,
        "window": ["id": "init", "title": title],
    ]
    if let versionType { json["versionType"] = versionType }
    return json
}

// MARK: - identity (the app's real version + channel are NOT in Info.plist)

@Suite("WeChat DevTools identity")
struct WeChatDevToolsIdentityTests {

    /// The three channels as they really ship. `versionType` is the signal;
    /// nothing in Info.plist distinguishes them (2.02 reports `com.github.Electron`
    /// and version `36.6.0` on all three).
    @Test func readsVersionAndChannelFromPackageJSON() throws {
        let stable = try #require(AppScanner.weChatDevToolsIdentity(fromPackageJSON:
            wechatPackageJSON(version: "2.02.2608040", versionType: "0",
                              title: "微信开发者工具 Stable v2.02.2608040")))
        #expect(stable.version == "2.02.2608040")
        #expect(stable.channel == .stable)

        let rc = try #require(AppScanner.weChatDevToolsIdentity(fromPackageJSON:
            wechatPackageJSON(version: "2.02.2608031", versionType: "1",
                              title: "微信开发者工具 RC v2.02.2608031")))
        #expect(rc.version == "2.02.2608031")
        #expect(rc.channel == .rc)

        let nightly = try #require(AppScanner.weChatDevToolsIdentity(fromPackageJSON:
            wechatPackageJSON(version: "2.02.2608182", versionType: "2",
                              title: "微信开发者工具 Nightly v2.02.2608182")))
        #expect(nightly.version == "2.02.2608182")
        #expect(nightly.channel == .nightly)
    }

    /// The 2.01 (NW.js) generation, which is what an un-upgraded install still is.
    @Test func readsTheLegacyNWJSGeneration() throws {
        let identity = try #require(AppScanner.weChatDevToolsIdentity(fromPackageJSON:
            wechatPackageJSON(version: "2.01.2510290", versionType: "0",
                              title: "微信开发者工具 Stable v2.01.2510290")))
        #expect(identity.version == "2.01.2510290")
        #expect(identity.channel == .stable)
    }

    /// `com.github.Electron` is Electron's stock id — any app whose vendor forgot to
    /// change it lands on the same bundle id. The `package.json`'s own `appname` is
    /// what actually decides, so a different Electron app is never re-filed as
    /// WeChat DevTools (and never offered its installer).
    @Test func refusesAnotherElectronAppsPackageJSON() {
        #expect(AppScanner.weChatDevToolsIdentity(fromPackageJSON:
            wechatPackageJSON(version: "1.2.3", versionType: "0",
                              title: "Some Other App", appname: "someotherapp")) == nil)
    }

    /// An unrecognized `versionType` yields NO identity at all, rather than a
    /// version with a guessed `.stable` channel. The app then keeps its stock id,
    /// matches no recipe and reads "unknown" — the failure we want, because guessing
    /// stable for an unknown channel is how a cross-channel install happens.
    @Test func refusesAnUnknownChannelOutright() {
        #expect(AppScanner.weChatDevToolsIdentity(fromPackageJSON:
            wechatPackageJSON(version: "2.03.1", versionType: "7",
                              title: "微信开发者工具 Insider v2.03.1")) == nil)
    }

    /// With `versionType` gone entirely, the window title carries the same fact.
    @Test func fallsBackToTheWindowTitle() throws {
        let identity = try #require(AppScanner.weChatDevToolsIdentity(fromPackageJSON:
            wechatPackageJSON(version: "2.02.2608182", versionType: nil,
                              title: "微信开发者工具 Nightly v2.02.2608182")))
        #expect(identity.channel == .nightly)
        #expect(AppScanner.weChatDevToolsIdentity(fromPackageJSON:
            wechatPackageJSON(version: "2.02.1", versionType: nil,
                              title: "微信开发者工具 v2.02.1")) == nil)
    }
}

// MARK: - probe recipes (one shared endpoint, three channels)

@Suite("WeChat DevTools vendor probe")
struct WeChatDevToolsProbeTests {
    private func recipe(_ channel: ReleaseChannel) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == AppScanner.weChatDevToolsBundleID && $0.channel == channel
        })
    }

    /// Derived from the registry, not a hand-written list: every channel recipe this
    /// app has must read its OWN version out of the shared document.
    @Test func eachChannelReadsItsOwnVersion() throws {
        let expected: [ReleaseChannel: String] = [
            .stable: "2.02.2608040",
            .rc: "2.02.2608031",
            .nightly: "2.02.2608182",
        ]
        let recipes = VendorProbeRegistry.recipes
            .filter { $0.bundleID == AppScanner.weChatDevToolsBundleID }
        #expect(Set(recipes.map(\.channel)) == Set(expected.keys))
        for recipe in recipes {
            #expect(VendorProbeRecipe.extractVersion(
                from: wechatDevToolsConfigFixture, pattern: recipe.versionPattern)
                == expected[recipe.channel])
        }
    }

    /// `nightly-old` is the retired NW.js train sitting in the same document with a
    /// much lower version. The Nightly anchor closes its quote right after the id, so
    /// the prefix can't be read as a match.
    @Test func nightlyDoesNotMatchTheRetiredNightlyOldTrain() throws {
        let recipe = try self.recipe(.nightly)
        #expect(VendorProbeRecipe.extractVersion(
            from: wechatDevToolsConfigFixture, pattern: recipe.versionPattern) != "2.01.2602282")
    }

    /// Each channel's install must resolve ITS arm64 pkg. Stable and RC are served
    /// from the same directory and differ only in the version, so a mis-anchored RC
    /// recipe would silently hand a Stable install to an RC user — the exact failure
    /// `ChannelArtifactProof` exists for.
    @Test func eachChannelResolvesItsOwnArm64Pkg() throws {
        let expected: [ReleaseChannel: String] = [
            .stable: "wechat_devtools_2.02.2608040_darwin_arm64.pkg",
            .rc: "wechat_devtools_2.02.2608031_darwin_arm64.pkg",
            .nightly: "wechat_devtools_2.02.2608182_darwin_arm64.pkg",
        ]
        for (channel, filename) in expected {
            let recipe = try self.recipe(channel)
            let install = try #require(recipe.install)
            #expect(install.kind == .pkg)
            guard case .bodyPattern(let pattern) = install.urlSource else {
                Issue.record("\(channel) install is not a bodyPattern")
                continue
            }
            let url = try #require(VendorProbeRecipe.extractVersion(
                from: wechatDevToolsConfigFixture, pattern: pattern))
            #expect(url.hasSuffix(filename))
            // x64 is served from the same block and listed FIRST — the arm64 anchor
            // is what keeps the Intel build out.
            #expect(!url.contains("_darwin_x64."))
        }
    }

    /// Every non-stable channel that can install must state how we know it isn't
    /// crossing trains (`RecipeHealthTests` enforces this globally; pinned here
    /// because RC's artifact is indistinguishable from Stable's by URL).
    @Test func nonStableChannelsCarryAChannelProof() throws {
        for channel in [ReleaseChannel.rc, .nightly] {
            #expect(ChannelProofRegistry.proofs[
                ChannelProofKey(AppScanner.weChatDevToolsBundleID, channel)] != nil)
        }
    }
}

// MARK: - changelog

@Suite("WeChat DevTools changelog")
struct WeChatDevToolsChangelogTests {

    /// One recipe per channel, each templating its own train's per-version document.
    @Test func eachChannelHasItsOwnVersionTemplatedRecipe() throws {
        for channel in [ReleaseChannel.stable, .rc, .nightly] {
            let recipe = try #require(ChangelogRecipeRegistry.recipe(
                forBundleID: AppScanner.weChatDevToolsBundleID, channel: channel))
            #expect(recipe.channel == channel)
            #expect(recipe.structuredFormat == .weChatDevToolsLog)
            let template = try #require(recipe.sourceTemplate)
            #expect(template.contains("/logs/\(channel.rawValue)_v{version}.json"))
            #expect(recipe.resolvedSource(forVersion: "2.02.2608031").absoluteString
                .hasSuffix("/logs/\(channel.rawValue)_v2.02.2608031.json"))
        }
    }

    /// The decoration every item carries — a literal "1." ordinal and a backticked
    /// marker — is stripped, while inline code that is part of the sentence survives.
    @Test func decodesOneReleaseWithItsItemsCleaned() throws {
        let changelog = try #require(StructuredChangelogDecoder.decode(
            wechatDevToolsRCLogFixture, format: .weChatDevToolsLog,
            channel: .rc, maxEntries: 40))
        let entry = try #require(changelog.entries.first)
        #expect(changelog.entries.count == 1)  // one document = one release
        #expect(entry.version == "2.02.2608031")
        #expect(entry.date == "2026-08-03")
        #expect(entry.items == [
            "🐛 问题修复",
            "切换 appid 相关反馈问题",
            "showToast 设置自定义图片时无法显示",
            "修复 第三方 AI 评测 `wx.login`",
        ])
    }

    /// A valid Nightly document is not a broken recipe merely because Tencent has
    /// not attached categorized changes to that build. Derive the decoder settings
    /// from the registered Nightly recipe and surface the vendor's own description.
    @Test func fallsBackToDescriptionWhenCategoriesAreEmpty() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: AppScanner.weChatDevToolsBundleID, channel: .nightly))
        let format = try #require(recipe.structuredFormat)
        let changelog = try #require(StructuredChangelogDecoder.decode(
            wechatDevToolsNightlyEmptyCategoriesFixture,
            format: format,
            channel: recipe.channel,
            maxEntries: recipe.maxEntries))
        let entry = try #require(changelog.entries.first)
        #expect(changelog.entries.count == 1)
        #expect(entry.version == "2.02.2609022")
        #expect(entry.date == "2026-09-02")
        #expect(entry.items == [
            "日常构建版本, 2.02.2603212 开始基于 Electron 36.6(对应 Chromium 136)， "
                + "2.01.2602282 且更早之前版本是基于 NW.js 0.54.1（Chromium 93)，"
                + "用于尽快修复缺陷和敏捷上线小的特性；开发自测验证，稳定性欠佳",
        ])
    }

    /// A marker is short by definition; a longer backticked token is the note's
    /// subject and must not be eaten.
    @Test func keepsLeadingInlineCodeThatIsNotAMarker() {
        #expect(StructuredChangelogDecoder.weChatDevToolsItem("1. `A` 新增 Electron 版本工具")
            == "新增 Electron 版本工具")
        #expect(StructuredChangelogDecoder.weChatDevToolsItem("1. `wx.chooseAddress` 无法选择地址")
            == "`wx.chooseAddress` 无法选择地址")
    }
}
