import Testing
import Foundation
@testable import DuoUpdaterCore

/// QQ音乐's probe and changelog, exercised against the vendor's real
/// `y.qq.com/download/download.js` body.
///
/// Both recipes are looked up from the registries rather than restated here, so a
/// pattern edited in `VendorProbeRecipe.swift` / `ChangelogRecipe.swift` is what
/// these assertions run.
///
/// The hazard this suite exists for is the DUPLICATE Mac object: the file carries
/// two `"Ftype":2,"Ftitle":"Mac"` records — the live client (ID 2) and a 2020-era
/// legacy record (ID 15) that is still parked in the table. Every pattern here is
/// first-match, so a rule that keys on `Ftitle` alone doesn't fail loudly, it
/// resolves a six-year-old version.
struct QQMusicProbeRecipeTests {

    /// Verbatim slice of `https://y.qq.com/download/download.js`, 2026-08-29 —
    /// key order, spacing and JSONP wrapper as the vendor emits them, with the
    /// objects that can collide kept and the unrelated ones (iPad / Android TV /
    /// 车载 / HarmonyOS / 腾讯视频 / …) dropped. Each survivor is a decoy:
    ///
    ///   * `ID:1`  Windows PC — comes FIRST, carries its own `发布时间`, and its
    ///                          version (22.5.2) is higher than the Mac client's.
    ///   * `ID:2`  Mac        — the real entry.
    ///   * `ID:3`  iPhone     — a `.ipa` link and a second `发布时间`.
    ///   * `ID:15` Mac        — the legacy 2020 record, same `Ftype`/`Ftitle`,
    ///                          linking the UNVERSIONED `QQMusicMac_Mgr.dmg`.
    private static let body = """
        MusicJsonCallback({"data":[\
        {"ID":1,"Ftype":1,"Ftitle":"Windows PC","Fversion":"最新版:22.5.2",\
        "Fpic":"https://y.qq.com/music/common/upload/T_Y_SOFTWARE/6908936.png",\
        "Fdesc":"「AI伴听」新增AI伴听模式，在左侧自定义功能栏可开启\\n|「其他」其他体验优化\\n|发布时间：2026-08-07",\
        "Flink1":"https://c.y.qq.com/cgi-bin/file_redirect.fcg?bid=dldir&file=ecosfile%2Fmusic_clntupate%2Fpc%2Fother%2FQQMusic_Setup_2252.exe&sign=1-2ba639cf-6a7b03b5",\
        "Flink2":"","Fintro":"","Fcode":""},\
        {"ID":2,"Ftype":2,"Ftitle":"Mac","Fversion":"最新版:11.8.1",\
        "Fpic":"https://y.qq.com/music/common/upload/T_Y_SOFTWARE/7293792.png",\
        "Fdesc":"「AI声景疗愈」新增AI声景疗愈模式，可在设置-疗愈模式开启\\n|「AI伴听」新增AI伴听模式，在左侧自定义功能栏可开启\\n|「其他」其他体验优化\\n|\\n\\n|发布时间：2026-08-03",\
        "Flink1":"https://c.y.qq.com/cgi-bin/file_redirect.fcg?bid=dldir&file=ecosfile%2Fmusic_clntupate%2Fmac%2Fother%2FQQMusicMac11.8.1Build01.dmg&sign=1-2b69b42bb1de172f44b04f87ba6567e28e5aa74872bba0149f7debe00a8d4619-6a7bded5",\
        "Flink2":"","Fintro":"","Fcode":""},\
        {"ID":3,"Ftype":3,"Ftitle":"iPhone","Fversion":"最新版:20.7.5",\
        "Fpic":"https://y.qq.com/music/common/upload/T_Y_SOFTWARE/2648276.png",\
        "Fdesc":"「AI助手识图推歌」万物皆可BGM，拿捏此刻氛围感\\n发布时间：2026-08-16",\
        "Flink1":"https://dldir1.qq.com/music/clntupate/ios/QQMusicIPhone5.8.1build04_yqq.ipa",\
        "Flink2":"https://itunes.apple.com/cn/app/qq-yin-le/id414603431?mt=8","Fintro":"","Fcode":""},\
        {"ID":15,"Ftype":2,"Ftitle":"Mac","Fversion":"最新版:7.0.0",\
        "Fpic":"https://y.qq.com/music/common/upload/T_Y_SOFTWARE/2446731.png",\
        "Fdesc":"- QQ音乐Mac7.0全新改版，极致炫美\\n- 添加动态皮肤支持\\n- 发布时间：2020-05-19",\
        "Flink1":"https://dldir1.qq.com/music/clntupate/mac/QQMusicMac_Mgr.dmg",\
        "Flink2":"","Fintro":null,"Fcode":""}]})
        """

    /// What the installed bundle reported on 2026-08-29 — read off
    /// `/Applications/QQMusic.app/Contents/Info.plist`. The build is here to
    /// document that the feed never mentions it (the `Build01` in the filename is
    /// a respin ordinal, not `CFBundleVersion`), which is what caps this recipe's
    /// resolution at the marketing version.
    private static let installedShortVersion = "11.8.1"
    private static let installedBuildVersion = "73276"

    private static let bundleID = "com.tencent.QQMusicMac"

    private static func recipe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID },
                     "no QQ音乐 recipe in the registry")
    }

    /// The installer URL the spec resolves out of `text`, or nil when it matches
    /// nothing. Records an issue rather than returning nil on a changed spec
    /// shape, so the nil-asserting tests below can't go vacuous.
    private static func installURL(in text: String) throws -> String? {
        let spec = try #require(recipe().install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("QQ音乐's install is no longer a body pattern; the nil assertions here are vacuous")
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
            Issue.record("QQ音乐 is no longer a response-body probe")
        }
        // The dmg holds `QQMusic.app` and nothing else — no daemon, no helper — so
        // a bundle swap is the whole update. A `.pkg` here would be wrong, and so
        // would `.dmg` if the vendor ever started shipping siblings.
        #expect(recipe.install?.kind == .dmg)
        // Tencent publishes no SHA-512; `checksumPattern` consumes base64 SHA-512.
        #expect(recipe.install?.checksumPattern == nil)
        // The filename's `Build01` is a respin ordinal, NOT the app's
        // `CFBundleVersion` (73276). Routing it into the build slot would compare
        // two different namespaces.
        #expect(recipe.versionIsBuild == false)
        // `发布时间：2026-08-03` is a bare zone-less day — a shape `ReleaseDate`
        // returns nil for. A pattern here would be a silent no-op, and an
        // unanchored one would take Windows' date (it precedes Mac in the body).
        #expect(recipe.publishedAtPattern == nil)
        #expect(ChangelogURLPolicy.displayable(recipe.changelogURL) != nil)
        // The probe URL is a JSONP data file, so it must not double as the user's
        // link.
        #expect(recipe.downloadURL != recipe.url)
        #expect(recipe.url.scheme == "https")
        // Every query parameter the site sends was measured inert (identical body,
        // `Last-Modified` and `Cache-Control`), so the registered URL carries none.
        #expect(recipe.url.query == nil)
    }

    // MARK: - version

    @Test func versionComesFromTheMacEntryNotThePlatformsAroundIt() throws {
        let version = VendorProbeRecipe.extractVersion(
            from: Self.body, pattern: try Self.recipe().versionPattern)
        #expect(version == "11.8.1")
        // Not the Windows client's, which is first in the body and higher.
        #expect(version != "22.5.2")
        // Not iPhone's, and not the legacy 2020 Mac record's.
        #expect(version != "20.7.5")
        #expect(version != "7.0.0")
    }

    /// The feed's answer must not read as older than the copy on disk — the
    /// `RecipeSanity.remoteBehindInstalled` shape, checked here on the fixture so
    /// a pattern that starts capturing the legacy record fails offline.
    @Test func resolvedVersionIsNotBehindTheInstalledCopy() throws {
        let version = try #require(VendorProbeRecipe.extractVersion(
            from: Self.body, pattern: try Self.recipe().versionPattern))
        #expect(!VersionComparator.isNewer(Self.installedShortVersion, than: version))
    }

    /// The feed states no build, so a marketing tie has to answer "not newer".
    /// This is the whole reason a same-marketing respin is invisible rather than a
    /// phantom update, and it is the assertion that would flip if someone routed
    /// the filename's `Build01` into the build slot.
    @Test func aMarketingTieWithNoRemoteBuildIsNotAnUpdate() throws {
        let version = try #require(VendorProbeRecipe.extractVersion(
            from: Self.body, pattern: try Self.recipe().versionPattern))
        let remote = VersionSide(marketing: version, build: nil)
        let installed = VersionSide(
            marketing: Self.installedShortVersion, build: Self.installedBuildVersion)
        #expect(!VersionComparator.isNewer(remote, than: installed))
        #expect(!VersionComparator.isNewer(installed, than: remote))
    }

    /// The legacy `ID:15` record is the reason both patterns key on the versioned
    /// filename. With the live entry gone, NOTHING may resolve — least of all
    /// 7.0.0, which is otherwise the closest thing in the body.
    @Test func withoutTheLiveMacEntryNoVersionOrURLIsInvented() throws {
        guard let range = Self.body.range(of: ",{\"ID\":2,") ,
              let end = Self.body.range(of: ",{\"ID\":3,") else {
            Issue.record("fixture no longer contains the ID 2 / ID 3 objects"); return
        }
        let withoutMac = String(Self.body[Self.body.startIndex..<range.lowerBound])
            + String(Self.body[end.lowerBound...])
        #expect(VendorProbeRecipe.extractVersion(
            from: withoutMac, pattern: try Self.recipe().versionPattern) == nil)
        #expect(try Self.installURL(in: withoutMac) == nil)
    }

    // MARK: - install URL

    @Test func installURLIsTheMacDMGRedirectOnTheVendorHost() throws {
        #expect(try Self.installURL(in: Self.body) == """
            https://c.y.qq.com/cgi-bin/file_redirect.fcg?bid=dldir&\
            file=ecosfile%2Fmusic_clntupate%2Fmac%2Fother%2FQQMusicMac11.8.1Build01.dmg&\
            sign=1-2b69b42bb1de172f44b04f87ba6567e28e5aa74872bba0149f7debe00a8d4619-6a7bded5
            """)
    }

    /// The `sign` token is what the redirect needs; a pattern that stopped at
    /// `.dmg` would resolve a URL the CDN refuses.
    @Test func installURLKeepsTheSignedQueryTail() throws {
        let url = try #require(try Self.installURL(in: Self.body))
        #expect(url.contains("&sign="))
        #expect(!url.hasSuffix(".dmg"))
    }

    /// Both the version and the install URL must name the SAME release — the
    /// property the whole recipe rests on, since a drift here downloads and
    /// installs a build the row never claimed.
    @Test func versionAndInstallURLNameTheSameRelease() throws {
        let version = try #require(VendorProbeRecipe.extractVersion(
            from: Self.body, pattern: try Self.recipe().versionPattern))
        let url = try #require(try Self.installURL(in: Self.body))
        #expect(url.contains("QQMusicMac\(version)Build"))
    }

    /// Windows ships an `.exe` and iPhone an `.ipa` off the same body; neither may
    /// ever be what the installer downloads.
    @Test func installURLNeverResolvesAnotherPlatformsArtifact() throws {
        let url = try #require(try Self.installURL(in: Self.body))
        #expect(!url.contains(".exe"))
        #expect(!url.contains(".ipa"))
        #expect(!url.contains("QQMusicMac_Mgr"))
    }

    // MARK: - changelog

    private static func changelogRecipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID),
                     "no QQ音乐 changelog recipe in the registry")
    }

    private static func parsed() throws -> Changelog {
        try #require(ChangelogExtractor.extract(from: body, using: changelogRecipe()))
    }

    @Test func changelogRecipeReadsTheSameJSONPDataFile() throws {
        let recipe = try Self.changelogRecipe()
        #expect(recipe.mode == .json)
        #expect(recipe.source.absoluteString == "https://y.qq.com/download/download.js")
        #expect(recipe.channel == nil)
        // The file states only the current release per platform — there is no
        // history to page through.
        #expect(recipe.maxEntries == 1)
    }

    /// One entry, the live Mac client's — not the legacy 2020 record that shares
    /// its `Ftype` and `Ftitle`, and not Windows' or iPhone's.
    @Test func onlyTheLiveMacEntryIsExtracted() throws {
        let log = try Self.parsed()
        #expect(log.entries.map(\.version) == ["11.8.1"])
        #expect(log.entries.map(\.date) == ["2026-08-03"])
    }

    /// The bullets are `Fdesc`'s `\n|`-separated segments, JSON-unescaped — with
    /// the trailing `\n|\n\n|发布时间：…` run eaten by the entry pattern rather
    /// than shown as a note.
    @Test func bulletsAreTheSeparatedSegmentsAndNothingElse() throws {
        let entry = try #require(try Self.parsed().entries.first)
        #expect(entry.items == [
            "「AI声景疗愈」新增AI声景疗愈模式，可在设置-疗愈模式开启",
            "「AI伴听」新增AI伴听模式，在左侧自定义功能栏可开启",
            "「其他」其他体验优化",
        ])
        for item in entry.items {
            #expect(!item.contains("发布时间"))
            #expect(!item.contains("\\n"), "a JSON escape leaked into a rendered note")
            #expect(!item.contains("|"))
        }
    }

    /// A `Fdesc` with no separators at all must still produce its one note — the
    /// reason the single item pattern needs no redundant sibling.
    @Test func anUnseparatedDescriptionYieldsTheWholeStringAsOneNote() throws {
        let body = """
            {"ID":2,"Ftype":2,"Ftitle":"Mac","Fversion":"最新版:12.0.0",\
            "Fdesc":"整体体验优化\\n发布时间：2026-09-01",\
            "Flink1":"https://c.y.qq.com/cgi-bin/file_redirect.fcg?file=QQMusicMac12.0.0Build01.dmg&sign=x"}
            """
        let log = try #require(
            ChangelogExtractor.extract(from: body, using: try Self.changelogRecipe()))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "12.0.0")
        #expect(entry.items == ["整体体验优化"])
    }

    /// A note carrying an escaped quote must stay ONE item, not be cut in half.
    /// No live note carries a quote today, so this fixture is the only thing
    /// standing between the pattern and that.
    @Test func anEscapedQuoteInsideANoteDoesNotSplitIt() throws {
        let body = """
            {"ID":2,"Ftype":2,"Ftitle":"Mac","Fversion":"最新版:12.0.0",\
            "Fdesc":"她说\\"你好\\"，然后走了\\n|第二条\\n|发布时间：2026-09-01",\
            "Flink1":"https://c.y.qq.com/cgi-bin/file_redirect.fcg?file=QQMusicMac12.0.0Build01.dmg&sign=x"}
            """
        let log = try #require(
            ChangelogExtractor.extract(from: body, using: try Self.changelogRecipe()))
        let entry = try #require(log.entries.first)
        // `.json` decoding turns the escapes back into real quotes.
        #expect(entry.items == ["她说\"你好\"，然后走了", "第二条"])
    }
}
