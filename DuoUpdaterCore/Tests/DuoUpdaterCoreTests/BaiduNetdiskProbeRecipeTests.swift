import Testing
import Foundation
@testable import DuoUpdaterCore

/// 百度网盘's probe, exercised against the vendor's real `?do=client` body.
///
/// The recipe is looked up from the registry rather than restated here, so a
/// pattern edited in `VendorProbeRecipe.swift` is what these assertions run.
///
/// The hazard this suite exists for is ORDERING: the endpoint answers with one
/// object per Baidu product line, keys in ALPHABETICAL order, and
/// `genflow-pro-pc-mac` — a different product whose macOS artifact is also
/// `…_arm64.dmg`, on the same CDN, under the same `/issue/netdisk/` prefix —
/// sorts BEFORE `mac`. Every pattern here is first-match, so a rule that is one
/// token short doesn't fail loudly, it resolves 库库GenFlow's build instead.
struct BaiduNetdiskProbeRecipeTests {

    /// Verbatim slice of `https://pan.baidu.com/disk/cmsdata?do=client`,
    /// 2026-08-29 — key order, spacing and all, with the four objects that can
    /// collide kept and the unrelated ones (android / tv / iphone / web / …)
    /// dropped. Each surviving object is a decoy the patterns must survive:
    ///
    ///   * `genflow-pro-pc-mac` — same CDN, same path prefix, `_arm64.dmg`
    ///                            filename, and it comes FIRST.
    ///   * `guanjia`           — the Windows client, on a FOUR-segment version
    ///                            (8.7.9.102) that shares its first three with mac.
    ///   * `linux`             — an older version (8.7.0) under a sibling
    ///                            `LinuxGuanjia/` path.
    ///   * `mac`               — the real entry, publishing x64, arm64 and
    ///                            universal side by side.
    private static let body = """
        {"genflow-pro-pc-mac":{"title":"库库GenFlowMac电脑客户端V1.3.6",\
        "version":"库库GenFlowMac电脑客户端V1.3.6",\
        "url":"https://pkg-ant.baidu.com/issue/netdisk/MACGenFlowPro/1.3.6/KukuAI_1.3.6_x64.dmg",\
        "url_1":"https://pkg-ant.baidu.com/issue/netdisk/MACGenFlowPro/1.3.6/KukuAI_1.3.6_arm64.dmg",\
        "url_2":"https://pkg-ant.baidu.com/issue/netdisk/MACGenFlowPro/1.3.6/KukuAI_1.3.6_universal.dmg",\
        "publish":"2026-08-28 23:01:48","size":"161.8M","system":"Mac OS X 13.0+","feature_tips":""},\
        "guanjia":{"title":"百度网盘Windows电脑客户端V8.7.9.102",\
        "version":"百度网盘Windows电脑客户端V8.7.9.102",\
        "url":"https://issuepcdn.baidupcs.com/issue/netdisk/yunguanjia/BaiduNetdisk_8.7.9.102.exe",\
        "url_1":"https://issuepcdn.baidupcs.com/issue/netdisk/yunguanjia/BaiduNetdisk_7.12.3.5.exe",\
        "url_2":"https://issuepcdn.baidupcs.com/issue/netdisk/yunguanjia/x64/BaiduNetdisk_8.7.9.102_x64.exe",\
        "publish":"2026-08-28 15:45:00","size":"513M","system":"XP/vista/win7/win8/win10/win11",\
        "feature_tips":""},\
        "linux":{"title":"百度网盘Linux电脑客户端V8.7.0","version":"百度网盘Linux电脑客户端V8.7.0",\
        "url":"https://pkg-ant.baidu.com/issue/netdisk/LinuxGuanjia/8.7.0/baidunetdisk-8.7.0.x86_64.rpm",\
        "url_1":"https://pkg-ant.baidu.com/issue/netdisk/LinuxGuanjia/8.7.0/baidunetdisk_8.7.0_amd64.deb",\
        "url_2":"","publish":"2026-08-05 20:27:00","size":"263.1M","system":"Ubuntu V18.04",\
        "feature_tips":""},\
        "mac":{"title":"百度网盘Mac电脑客户端V8.7.9","version":"百度网盘Mac电脑客户端V8.7.9",\
        "url":"https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_x64.dmg",\
        "url_1":"https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_arm64.dmg",\
        "url_2":"https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_universal.dmg",\
        "publish":"2026-08-28 14:39:00","size":"444.2M","system":"Mac OS X 10.13+","feature_tips":""}}
        """

    /// What the installed bundle reported on 2026-08-29 — read off
    /// `/Applications/BaiduNetdisk_mac.app/Contents/Info.plist`. The build is here
    /// to document that the feed never mentions it, which is what caps this
    /// recipe's resolution at the marketing version.
    private static let installedShortVersion = "8.7.9"
    private static let installedBuildVersion = "473"

    private static let bundleID = "com.baidu.BaiduNetdisk-mac"

    private static func recipe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID },
                     "no 百度网盘 recipe in the registry")
    }

    /// The installer URL the spec resolves out of `text`, or nil when it matches
    /// nothing. Records an issue rather than returning nil on a changed spec
    /// shape, so the nil-asserting tests below can't go vacuous.
    private static func installURL(in text: String) throws -> String? {
        let spec = try #require(recipe().install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("百度网盘's install is no longer a body pattern; the nil assertions here are vacuous")
            return nil
        }
        return VendorProbeRecipe.extractVersion(from: text, pattern: pattern)
    }

    // MARK: - registry shape

    @Test func registersExactlyOneStableRecipe() throws {
        let all = VendorProbeRegistry.recipes.filter { $0.bundleID == Self.bundleID }
        #expect(all.count == 1)
        let recipe = try #require(all.first)
        #expect(recipe.channel == .stable)
        #expect(recipe.variant == nil)
        // The endpoint answers anonymously; keeping it that way is what stops this
        // machine's identifiers from reaching a verify report.
        #expect(recipe.identities.isEmpty && recipe.track == nil)
        if case .responseBody = recipe.mode {} else {
            Issue.record("百度网盘 is no longer a response-body probe")
        }
        #expect(recipe.install?.kind == .dmg)
        // Baidu publishes no SHA-512; `checksumPattern` consumes base64 SHA-512.
        #expect(recipe.install?.checksumPattern == nil)
        // The `publish` field is space-separated and zone-less — a shape
        // `ReleaseDate` returns nil for. A pattern here would be a silent no-op.
        #expect(recipe.publishedAtPattern == nil)
        // The vendor's 版本更新 page, not the JSON endpoint the notes are parsed
        // from — a web view is what this field feeds.
        #expect(recipe.changelogURL?.absoluteString == "https://pan.baidu.com/disk/version")
        #expect(ChangelogURLPolicy.displayable(recipe.changelogURL) != nil)
        // The probe URL is a JSON API, so it must not double as the user's link.
        #expect(recipe.downloadURL != recipe.url)
        #expect(recipe.url.scheme == "https")
    }

    // MARK: - version

    @Test func versionComesFromTheMacEntryNotTheProductsAroundIt() throws {
        let version = VendorProbeRecipe.extractVersion(
            from: Self.body, pattern: try Self.recipe().versionPattern)
        #expect(version == "8.7.9")
        // Not 库库GenFlow's, which is first in the body and also `_arm64.dmg`.
        #expect(version != "1.3.6")
        // Not the Windows client's four-segment version, nor linux's older one.
        #expect(version != "8.7.9.102")
        #expect(version != "8.7.0")
    }

    /// The feed's answer must not read as older than the copy on disk — the
    /// `RecipeSanity.remoteBehindInstalled` shape, checked here on the fixture so
    /// a pattern that starts capturing the wrong product fails offline.
    @Test func resolvedVersionIsNotBehindTheInstalledCopy() throws {
        let version = try #require(VendorProbeRecipe.extractVersion(
            from: Self.body, pattern: try Self.recipe().versionPattern))
        #expect(!VersionComparator.isNewer(Self.installedShortVersion, than: version))
    }

    /// The feed states no build, so a marketing tie has to answer "not newer".
    /// This is the whole reason a build-only respin is invisible rather than a
    /// phantom update, and it is the assertion that would flip if someone routed
    /// this recipe's marketing string into the build slot.
    @Test func aMarketingTieWithNoRemoteBuildIsNotAnUpdate() throws {
        let version = try #require(VendorProbeRecipe.extractVersion(
            from: Self.body, pattern: try Self.recipe().versionPattern))
        let remote = VersionSide(marketing: version, build: nil)
        let installed = VersionSide(
            marketing: Self.installedShortVersion, build: Self.installedBuildVersion)
        #expect(!VersionComparator.isNewer(remote, than: installed))
        #expect(!VersionComparator.isNewer(installed, than: remote))
    }

    /// The backreference is the recipe's one non-obvious mechanism: it requires
    /// the directory version and the filename version to name the same release.
    /// If `NSRegularExpression` ever stopped honouring `\1` the pattern would
    /// simply stop matching — which this catches — rather than start matching
    /// something else.
    @Test func aDirectoryFilenameVersionMismatchResolvesNothing() throws {
        let skewed = Self.body.replacingOccurrences(
            of: "MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_arm64.dmg",
            with: "MACguanjia/8.7.9/BaiduNetdisk_mac_9.9.9_arm64.dmg")
        #expect(VendorProbeRecipe.extractVersion(
            from: skewed, pattern: try Self.recipe().versionPattern) == nil)
    }

    // MARK: - install URL

    @Test func installURLIsTheMacArm64ArtifactOnTheVendorCDN() throws {
        #expect(try Self.installURL(in: Self.body)
            == "https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_arm64.dmg")
    }

    /// Both the version and the install URL must name the SAME release — the
    /// property the whole recipe rests on, since a drift here downloads and
    /// installs a build the row never claimed.
    @Test func versionAndInstallURLNameTheSameRelease() throws {
        let version = try #require(VendorProbeRecipe.extractVersion(
            from: Self.body, pattern: try Self.recipe().versionPattern))
        let url = try #require(try Self.installURL(in: Self.body))
        #expect(url.contains("/MACguanjia/\(version)/"))
        #expect(url.hasSuffix("BaiduNetdisk_mac_\(version)_arm64.dmg"))
    }

    /// With the mac entry gone the spec must resolve NOTHING — not 库库GenFlow's
    /// arm64 dmg, which is otherwise the closest thing in the body.
    @Test func withoutTheMacEntryNoInstallURLIsInvented() throws {
        guard let macRange = Self.body.range(of: ",\"mac\":{") else {
            Issue.record("fixture no longer contains a `mac` object"); return
        }
        let withoutMac = String(Self.body[Self.body.startIndex..<macRange.lowerBound]) + "}"
        #expect(try Self.installURL(in: withoutMac) == nil)
        #expect(VendorProbeRecipe.extractVersion(
            from: withoutMac, pattern: try Self.recipe().versionPattern) == nil)
    }

    /// x64 and universal are published beside arm64 under the same version; the
    /// spec must pin the architecture rather than take whichever comes first.
    @Test func installURLNeverResolvesTheX64OrUniversalSibling() throws {
        let url = try #require(try Self.installURL(in: Self.body))
        #expect(!url.contains("_x64.dmg"))
        #expect(!url.contains("_universal.dmg"))
    }

    // MARK: - changelog

    /// Four entries lifted VERBATIM out of
    /// `https://pan.baidu.com/disk/cmsdata?platform=mac&page=1&num=100`
    /// (2026-08-29) — compact spacing and key order exactly as the vendor emits
    /// them, wrapped in the `list` array they arrive in. Chosen because each is a
    /// shape the patterns have to survive:
    ///
    ///   * 8.7.9 — the ordinary case: one bullet in `more`.
    ///   * 8.7.0 — two bullets, so an item pattern that stops after one shows up.
    ///   * 4.54.9 — `more` is EMPTY and the real note sits in the detail object's
    ///     `title`. 11 of the 100 live releases look like this. Capturing only the
    ///     `more` array would not leave them blank — the extractor drops an entry
    ///     whose item patterns yield nothing — it would drop them from the
    ///     changelog outright, which is why the fallback pattern is load-bearing
    ///     and why `theTitleFallbackIsWhatKeepsThoseReleasesAtAll` exists.
    ///   * 4.3.0 — the older shape: `feature_tips` sorts BEFORE `more` inside
    ///     `detail`, and the version label carries a space (`客户端 V4.3.0`).
    private static let changelogBody = """
        {"errmsg":"","errno":0,"errorno":0,"list":[\
        {"detail":[{"more":["【团队空间】空间布局全新改版，新增大图视图模式，并支持视频的滑动预览"],\
        "stable":true,"title":"百度网盘全新升级"}],"publish":"2026-08-28 14:39:00","size":"444.2M",\
        "system":"Mac OS X 10.13+","title":"百度网盘Mac电脑客户端V8.7.9",\
        "url":"https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_x64.dmg",\
        "url_1":"https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/8.7.9/BaiduNetdisk_mac_8.7.9_arm64.dmg",\
        "version":"百度网盘Mac电脑客户端V8.7.9"},\
        {"detail":[{"more":["【时光轴】端内图片支持时光轴模式，支持按时间线和标签回溯图片，查找更高效",\
        "【悬浮球】一键轻松截取长页面，信息记录更完整；新增独立悬浮提示，传输进度看得见"],\
        "stable":true,"title":"百度网盘全新升级"}],"publish":"2026-08-07 19:01:48","size":"421.9M",\
        "system":"Mac OS X 10.13+","title":"百度网盘Mac电脑客户端V8.7.0",\
        "url":"https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/8.7.0/BaiduNetdisk_mac_8.7.0_x64.dmg",\
        "url_1":"https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/8.7.0/BaiduNetdisk_mac_8.7.0_arm64.dmg",\
        "version":"百度网盘Mac电脑客户端V8.7.0"},\
        {"detail":[{"more":[],"stable":true,"title":"百度网盘优化了一些已知的体验问题，欢迎升级体验~"}],\
        "publish":"2025-10-30 17:45:42","size":"302M","system":"Mac OS X 10.13+",\
        "title":"百度网盘Mac电脑客户端V4.54.9",\
        "url":"https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/4.54.9/BaiduNetdisk_mac_4.54.9_x64.dmg",\
        "url_1":"https://pkg-ant.baidu.com/issue/netdisk/MACguanjia/4.54.9/BaiduNetdisk_mac_4.54.9_arm64.dmg",\
        "version":"百度网盘Mac电脑客户端V4.54.9"},\
        {"detail":[{"feature_tips":"mac版可以xxx啦",\
        "more":["企业版：群组文件功能优化，管理成员更方便！","同步空间：优化了同步目录设置的流程以及修复了部分同步异常问题"],\
        "title":"更新内容："}],"publish":"2021-12-06 12:00:00","size":"142M","system":"Mac OS X 10.10+",\
        "title":"百度网盘Mac电脑客户端 V4.3.0",\
        "url":"https://issuepcdn.baidupcs.com/issue/netdisk/MACguanjia/BaiduNetdisk_mac_4.3.0.dmg",\
        "url_1":"https://issuepcdn.baidupcs.com/issue/netdisk/MACguanjia/BaiduNetdisk_mac_4.3.0.dmg",\
        "version":"百度网盘Mac电脑客户端 V4.3.0"}],"total":145}
        """

    private static func changelogRecipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID),
                     "no 百度网盘 changelog recipe in the registry")
    }

    private static func parsed() throws -> Changelog {
        try #require(ChangelogExtractor.extract(from: changelogBody, using: changelogRecipe()))
    }

    @Test func changelogRecipeReadsTheMacTabsOwnEndpoint() throws {
        let recipe = try Self.changelogRecipe()
        #expect(recipe.mode == .json)
        #expect(recipe.source.absoluteString
            == "https://pan.baidu.com/disk/cmsdata?platform=mac&page=1&num=40")
        // `platform=mac` is the whole reason this returns Mac notes rather than
        // the Windows client's; losing it is silent, so pin it.
        #expect(recipe.source.query?.contains("platform=mac") == true)
        #expect(recipe.newestLast == false, "the feed is newest-first")
        #expect(recipe.channel == nil)
    }

    @Test func everyEntryIsExtractedWithItsVersionAndDate() throws {
        let log = try Self.parsed()
        #expect(log.entries.map(\.version) == ["8.7.9", "8.7.0", "4.54.9", "4.3.0"])
        #expect(log.entries.map(\.date) == [
            "2026-08-28 14:39:00", "2026-08-07 19:01:48",
            "2025-10-30 17:45:42", "2021-12-06 12:00:00",
        ])
    }

    /// The bullets are `more`'s elements — not the keys around them, and not the
    /// generic marketing `title` sitting in the same object.
    @Test func bulletsComeFromMoreAndNothingElseInTheObject() throws {
        let entries = try Self.parsed().entries
        #expect(entries[0].items == ["【团队空间】空间布局全新改版，新增大图视图模式，并支持视频的滑动预览"])
        #expect(entries[1].items.count == 2)
        #expect(entries[1].items[1] == "【悬浮球】一键轻松截取长页面，信息记录更完整；新增独立悬浮提示，传输进度看得见")
        for entry in entries {
            #expect(!entry.items.contains("stable"))
            #expect(!entry.items.contains("more"))
            #expect(!entry.items.contains("title"))
            #expect(!entry.items.contains("百度网盘全新升级"),
                    "the generic detail title must not be shown when `more` has bullets")
        }
    }

    /// 11 of 100 live releases ship an empty `more` with the real note in the
    /// detail `title`. The ordered fallback is what keeps those from rendering as
    /// blank entries.
    @Test func anEmptyMoreFallsBackToTheDetailTitle() throws {
        let entry = try #require(try Self.parsed().entries.first { $0.version == "4.54.9" })
        #expect(entry.items == ["百度网盘优化了一些已知的体验问题，欢迎升级体验~"])
    }

    /// The older records put `feature_tips` ahead of `more` inside `detail` and
    /// space the version label — both would break a pattern that assumed the
    /// recent shape.
    @Test func theOlderKeyOrderAndSpacedVersionLabelStillParse() throws {
        let entry = try #require(try Self.parsed().entries.first { $0.version == "4.3.0" })
        #expect(entry.items == [
            "企业版：群组文件功能优化，管理成员更方便！",
            "同步空间：优化了同步目录设置的流程以及修复了部分同步异常问题",
        ])
        #expect(!entry.items.contains("mac版可以xxx啦"))
        #expect(!entry.items.contains("更新内容："))
    }

    /// The fallback pattern is load-bearing, and this is the test that says so.
    ///
    /// Asserting "no parsed entry has empty items" would NOT say it: the extractor
    /// refuses to append an entry whose item patterns yield nothing
    /// (`guard !noteHits.isEmpty`), so such an entry can never reach `entries` and
    /// that assertion passes no matter what the recipe does. The regression the
    /// fallback prevents is a release going MISSING, so the test has to rebuild the
    /// recipe without the fallback and watch 4.54.9 disappear.
    @Test func theTitleFallbackIsWhatKeepsThoseReleasesAtAll() throws {
        let real = try Self.changelogRecipe()
        #expect(real.itemPatterns.count == 2,
                "the fallback this test removes is gone; it now proves nothing")
        let bulletsOnly = ChangelogRecipe(
            bundleID: real.bundleID,
            source: real.source,
            entryPattern: real.entryPattern,
            itemPatterns: [real.itemPatterns[0]],
            mode: real.mode,
            maxEntries: real.maxEntries)
        let stripped = try #require(
            ChangelogExtractor.extract(from: Self.changelogBody, using: bulletsOnly))
        // Not "4.54.9 is blank" — it is not there at all.
        let full = try Self.parsed().entries.count
        #expect(!stripped.entries.contains { $0.version == "4.54.9" })
        #expect(stripped.entries.count == full - 1)
    }

    /// A note carrying an escaped quote must stay ONE item, not vanish.
    ///
    /// `[^"]+` stops at the backslash's quote, and because the array's other
    /// elements still match, `firstNonEmptyItemHits` is satisfied and never tries
    /// the fallback — the entry simply renders with fewer notes than the vendor
    /// published, which nothing reports. No live item carries a quote today, so
    /// this fixture is the only thing standing between the pattern and that.
    @Test func anEscapedQuoteInsideANoteDoesNotSwallowIt() throws {
        let body = """
            {"list":[{"detail":[{"more":["她说\\"你好\\"，然后走了","第二条"],            "stable":true,"title":"百度网盘全新升级"}],"publish":"2026-08-28 14:39:00",            "version":"百度网盘Mac电脑客户端V9.0.0"}]}
            """
        let log = try #require(
            ChangelogExtractor.extract(from: body, using: try Self.changelogRecipe()))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "9.0.0")
        // `.json` decoding turns the escapes back into real quotes.
        #expect(entry.items == ["她说\"你好\"，然后走了", "第二条"])
    }
}
