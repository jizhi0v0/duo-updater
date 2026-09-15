import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// Version-templated changelog recipes (`sourceTemplate != nil`) fetch the page
/// the sweep's version selects, so two things about them differ from every other
/// recipe: their version is not comparable across sweeps, and when they have no
/// version the reason has to be named.
@Suite struct TemplatedChangelogVerifyTests {

    private static let templated = ChangelogRecipeRegistry.recipes.filter { $0.sourceTemplate != nil }

    /// `matchesPage` is what the sweep records as `headingMatchesPage`: true when
    /// the heading resolves to the page that was requested, nil when not recorded.
    private func changelogFinding(
        _ recipe: ChangelogRecipe, version: String, matchesPage: Bool? = nil
    ) -> Finding {
        Finding(
            recipeID: recipe.recipeID, registry: .changelog, bundleID: recipe.bundleID,
            channel: recipe.channel?.rawValue ?? "-", status: .ok, version: version,
            endpointHost: "example.invalid", entryCount: 1, headingMatchesPage: matchesPage)
    }

    private func source(
        _ registry: Registry, _ bundleID: String, _ channel: String,
        status: FindingStatus, failureKind: String? = nil
    ) -> Finding {
        Finding(
            recipeID: "\(registry.rawValue):\(bundleID):\(channel)", registry: registry,
            bundleID: bundleID, channel: channel, status: status, failureKind: failureKind,
            endpointHost: "example.invalid")
    }

    // MARK: - BACKWARDS

    /// A machine on an older minor reads an older page than the one the baseline
    /// was recorded from. Recorded 5.1, then 4.5 on three sweeps, each heading a
    /// reading of its own page: no complaint, no `warn`, no streak. 5.1 and 4.5
    /// differ in every component, so they resolve to different pages under every
    /// template. Derived from the registry, so every templated recipe is held to
    /// it as recipes come and go.
    ///
    /// Mutation: delete the `!Self.readDifferentPages(…),` line from `reconcile`.
    @Test func aTemplatedChangelogOnAnOlderPageIsNotGoingBackwards() throws {
        try #require(!Self.templated.isEmpty)
        #expect(VersionComparator.isNewer("5.1", than: "4.5"))
        for recipe in Self.templated {
            // Otherwise the lineage exemption would pass this, not the templated one.
            #expect(!VendorProbeRegistry.ordersByLineage(bundleID: recipe.bundleID),
                    "\(recipe.recipeID)")
            var baseline = Baseline()
            _ = Verify.foldingBaselineComplaints(
                [changelogFinding(recipe, version: "5.1", matchesPage: true)], into: &baseline)
            for _ in 1...3 {
                let out = Verify.foldingBaselineComplaints(
                    [changelogFinding(recipe, version: "4.5", matchesPage: true)], into: &baseline)
                #expect(!out[0].warnings.contains { $0.contains("BACKWARDS") }, "\(recipe.recipeID)")
                #expect(out[0].status == .ok, "\(recipe.recipeID)")
            }
            #expect(baseline.streak(recipe.recipeID) == 0, "\(recipe.recipeID)")
            #expect(!baseline.isReportable(recipe.recipeID), "\(recipe.recipeID)")
        }
    }

    /// The exemption is scoped, not the check switched off: an untemplated
    /// changelog, and the probe row of an app whose changelog IS templated, still
    /// complain.
    ///
    /// Mutation: replace the body of `readDifferentPages` with `return true` (both
    /// go quiet). No one-line mutation silences either half, by construction:
    /// neither finding carries `headingMatchesPage`, neither id names a templated
    /// recipe, and an untemplated recipe has no templated page — three
    /// independent guards. This test pins them against a rewrite, not a slip.
    @Test func untemplatedChangelogsAndProbeRowsStillGoBackwards() throws {
        let untemplated = try #require(ChangelogRecipeRegistry.recipes.first {
            $0.sourceTemplate == nil && !VendorProbeRegistry.ordersByLineage(bundleID: $0.bundleID)
        })
        let templatedBundles = Set(Self.templated.map(\.bundleID))
        let probe = try #require(VendorProbeRegistry.recipes.first {
            templatedBundles.contains($0.bundleID) && $0.buildLineage == nil
        })
        let probeFinding = { (version: String) in
            Finding(
                recipeID: probe.recipeID, registry: .vendor, bundleID: probe.bundleID,
                channel: probe.channel.rawValue, status: .ok, version: version,
                endpointHost: "example.invalid")
        }

        var changelog = Baseline()
        _ = changelog.reconcile(changelogFinding(untemplated, version: "5.1"))
        #expect(changelog.reconcile(changelogFinding(untemplated, version: "4.5"))
            .contains { $0.contains("BACKWARDS") }, "\(untemplated.recipeID)")

        var vendor = Baseline()
        _ = vendor.reconcile(probeFinding("5.1"))
        #expect(vendor.reconcile(probeFinding("4.5"))
            .contains { $0.contains("BACKWARDS") }, "\(probe.recipeID)")
    }

    /// A template keyed on the whole `{version}` gives every version its own
    /// page, so re-deriving pages from two headings always answers "different".
    /// When the pattern slips from 155.0.2 to an older 155.0.1 entry while the
    /// sweep requested 155.0.2's page, the heading does NOT match the page, and
    /// that has to keep the check — nothing else sees it: the lag check compares
    /// major.minor, which is equal. Nil (not recorded) keeps it too. The pair is
    /// first shown to resolve to different pages and to slip past the lag check,
    /// so the test measures the flag and not a fixture that was already safe.
    ///
    /// Mutation: delete `finding.headingMatchesPage == true,` from
    /// `readDifferentPages` — the heading-derived comparison this PR shipped first.
    @Test func aSlippedHeadingOnAWholeVersionPageStillGoesBackwards() throws {
        let thunderbird = try #require(Self.templated.first {
            $0.bundleID == "org.mozilla.thunderbird" && $0.channel == .stable
        })
        try #require(thunderbird.sourceTemplate?.contains("{version}") == true)
        try #require(VersionComparator.isNewer("155.0.2", than: "155.0.1"))
        try #require(Baseline.templatedPage(thunderbird, forHeading: "155.0.2")
            != Baseline.templatedPage(thunderbird, forHeading: "155.0.1"))
        try #require(Verify.changelogLagComplaint(entry: "155.0.1", detected: "155.0.2") == nil)

        for matchesPage in [false, nil] as [Bool?] {
            var baseline = Baseline()
            _ = baseline.reconcile(changelogFinding(thunderbird, version: "155.0.2", matchesPage: true))
            #expect(baseline.reconcile(
                changelogFinding(thunderbird, version: "155.0.1", matchesPage: matchesPage))
                .contains { $0.contains("BACKWARDS") }, "headingMatchesPage=\(String(describing: matchesPage))")
        }
    }

    /// A template keyed on less than the whole version shares one page across
    /// versions, and an older heading on that same page is the element slip the
    /// check exists for — even when that heading does resolve to the page.
    /// Opera's `{major}` page and Xcode's betas under one `{appleDocVersion}`
    /// page — the latter headed "Xcode 27 Beta 6", as
    /// `XcodeReleaseNotesChangelogTests` pins. Both pairs are first shown to
    /// resolve to one page, so the test measures the page comparison.
    ///
    /// Mutations: `return previousPage != currentPage` → `return true` (both go
    /// quiet); drop `.drop { !$0.isNumber }` in `templatedPage` (Xcode's headings
    /// resolve to two junk URLs and go quiet).
    @Test func anOlderHeadingOnTheSamePageStillGoesBackwards() throws {
        let cases: [(bundleID: String, previous: String, current: String)] = [
            ("com.operasoftware.Opera", "135.0.5973.123", "135.0.5973.35"),
            ("com.apple.dt.Xcode", "Xcode 27 Beta 6", "Xcode 27 Beta 5"),
        ]
        for (bundleID, previous, current) in cases {
            let recipe = try #require(Self.templated.first { $0.bundleID == bundleID })
            try #require(VersionComparator.isNewer(previous, than: current), "\(bundleID)")
            let digits = { (v: String) in String(v.drop { !$0.isNumber }) }
            try #require(recipe.resolvedSource(forVersion: digits(previous))
                == recipe.resolvedSource(forVersion: digits(current)), "\(bundleID)")

            var baseline = Baseline()
            _ = baseline.reconcile(changelogFinding(recipe, version: previous, matchesPage: true))
            #expect(baseline.reconcile(changelogFinding(recipe, version: current, matchesPage: true))
                .contains { $0.contains("BACKWARDS") }, "\(recipe.recipeID)")
        }
    }

    /// A version with no digit names no page. Resolving it anyway gives a page
    /// named after the text ("…/release_notes/LTS/"), which differs from every real
    /// page and would read as "another page" — so the check keeps applying.
    ///
    /// Mutation: drop `, !digits.isEmpty` from `templatedPage`'s guard.
    @Test func aVersionWithNoDigitKeepsTheCheck() throws {
        let blender = try #require(Self.templated.first { $0.bundleID == "org.blenderfoundation.blender" })
        try #require(VersionComparator.isNewer("5.1", than: "LTS"))
        try #require(blender.resolvedSource(forVersion: "LTS") != blender.resolvedSource(forVersion: "5.1"))

        var baseline = Baseline()
        _ = baseline.reconcile(changelogFinding(blender, version: "5.1", matchesPage: true))
        #expect(baseline.reconcile(changelogFinding(blender, version: "LTS", matchesPage: true))
            .contains { $0.contains("BACKWARDS") })
    }

    // MARK: - skip reason

    private func recipe(_ bundleID: String, _ channel: ReleaseChannel?) throws -> ChangelogRecipe {
        try #require(Self.templated.first { $0.bundleID == bundleID && $0.channel == channel })
    }

    /// A probe for this recipe's channel ran and came back empty: the finding
    /// names it and its status, and does not claim the app is simply absent. A
    /// sibling channel's probe and another changelog row are not sources.
    ///
    /// Mutations: drop the `recipe.channel.map { … } ?? true` clause (the Stable
    /// probe is named too); replace the registry clause with `true` (the
    /// changelog row is named).
    @Test func aChannelRecipeNamesOnlyItsOwnChannelsSource() throws {
        let rc = try recipe("com.tencent.wechatdevtools", .rc)
        let detail = Verify.templatedSkipDetail(for: rc, versionSources: [
            source(.vendor, rc.bundleID, "rc", status: .infra, failureKind: "transport"),
            source(.vendor, rc.bundleID, "stable", status: .broken, failureKind: "versionPatternNoMatch"),
            source(.changelog, rc.bundleID, "rc", status: .broken, failureKind: "noEntries"),
        ])
        #expect(detail.contains("did not produce a version this sweep"))
        #expect(detail.contains("vendor:com.tencent.wechatdevtools:rc: infra (transport)"))
        #expect(!detail.contains(":stable"))
        #expect(!detail.contains("changelog:"))
        #expect(!detail.contains("app not installed"))
    }

    /// A channel-less recipe takes any source for its app, as `changelogVersion`
    /// does — vendor and GitHub alike.
    ///
    /// Mutations: `?? true` → `?? false` (nothing is named); drop
    /// `|| source.registry == .github` (the GitHub rule is not named).
    @Test func aChannelLessRecipeNamesEverySourceForItsApp() throws {
        let wechat = try recipe("com.tencent.xinWeChat", nil)
        let detail = Verify.templatedSkipDetail(for: wechat, versionSources: [
            source(.vendor, wechat.bundleID, "stable", status: .infra),
            source(.github, wechat.bundleID, "beta", status: .broken, failureKind: "httpStatus404"),
        ])
        #expect(detail.contains("vendor:com.tencent.xinWeChat:stable: infra"))
        #expect(detail.contains("github:com.tencent.xinWeChat:beta: broken (httpStatus404)"))
    }

    /// Nothing for this app ran: the existing text, verbatim.
    ///
    /// Mutation: drop `&& source.bundleID == recipe.bundleID` (another app's
    /// probe is named).
    @Test func noSourceForTheAppKeepsTheNotInstalledReason() throws {
        let blender = try recipe("org.blenderfoundation.blender", nil)
        let detail = Verify.templatedSkipDetail(for: blender, versionSources: [
            source(.vendor, "com.example.other", "stable", status: .infra),
        ])
        #expect(detail == "version-templated: no version available "
            + "(app not installed, and no version source ran this sweep)")
    }

    /// Through the sweep itself, which returns before any request when there is no
    /// version: the reason reaches the finding, the finding is `.skipped`, and a
    /// week of such sweeps leaves the row with no streak of either kind — so the
    /// probe's outage is not filed a second time from the changelog row.
    ///
    /// Mutations: pass `versionSources: []` to `templatedSkipDetail` inside
    /// `sweepChangelog` (the reason is lost); `status: .skipped` → `.infra` on
    /// that finding (the row ages into an infra report).
    @Test func theSweepCarriesTheReasonAndFilesNothing() async throws {
        let inkscape = try #require(Self.templated.first { $0.bundleID == "org.inkscape.Inkscape" })
        let probe = source(.vendor, inkscape.bundleID, inkscape.channel?.rawValue ?? "stable",
                           status: .infra, failureKind: "transport")
        let findings = await Verify.sweepChangelog(
            [inkscape], options: VerifyOptions(), versions: [:], versionSources: [probe])
        let finding = try #require(findings.first)
        #expect(findings.count == 1)
        #expect(finding.status == .skipped)
        #expect(finding.failureDetail?.contains(probe.recipeID) == true)

        var baseline = Baseline()
        let start = Date()
        for _ in 1...30 { _ = baseline.reconcile(finding) }
        #expect(baseline.streak(inkscape.recipeID) == 0)
        #expect(baseline.infraStreak(inkscape.recipeID) == 0)
        #expect(!baseline.isInfraReportable(
            inkscape.recipeID, now: start.addingTimeInterval(Baseline.infraWindow * 2)))
    }

    // MARK: - what the sweep records

    /// Through the real success path of `sweepChangelog`, against a stub that
    /// serves each page with a heading: the "match" page headed with the version
    /// in its own URL, the "slip" page headed 1.2.1 whatever it was requested for.
    /// The flag is set against the page requested, an untemplated recipe leaves it
    /// nil, and both finding rebuilds keep it.
    ///
    /// Mutations: `headingMatchesPage: nil` in `sweepChangelog` (match goes nil);
    /// compare against `recipe.resolvedSource(forVersion: top)` instead of
    /// `diagnostic.resolvedURL` (the slip reads as matching — re-deriving from the
    /// heading, the hole this flag closes); drop `headingMatchesPage:` from
    /// `adding(warning:)`, or from `observing(_:)` (that rebuild loses it).
    @Test func theSweepRecordsWhetherTheHeadingIsThePageItRequested() async throws {
        func recipe(_ name: String, template: String?) -> ChangelogRecipe {
            ChangelogRecipe(
                bundleID: "com.example.zz-templated-\(name)",
                source: URL(string: "https://stub.invalid/fixed/")!,
                entryPattern: #"<h1>(?<version>[0-9.]+)</h1>(?<body>.*?)(?=</body>)"#,
                itemPatterns: [#"<p>(?<item>.*?)</p>"#],
                maxEntries: 1,
                sourceTemplate: template)
        }
        let match = recipe("match", template: "https://stub.invalid/match/{version}/")
        let slip = recipe("slip", template: "https://stub.invalid/slip/{version}/")
        let fixed = recipe("fixed", template: nil)
        var options = VerifyOptions()
        options.perHostDelay = .zero

        let findings = await Verify.sweepChangelog(
            [match, slip, fixed], options: options,
            versions: [match.bundleID: "1.2.2", slip.bundleID: "1.2.2"],
            versionSources: [], session: HeadedPageStub.session)
        func finding(_ recipe: ChangelogRecipe) throws -> Finding {
            try #require(findings.first { $0.recipeID == recipe.recipeID })
        }

        let matched = try finding(match)
        #expect(matched.version == "1.2.2", "\(String(describing: matched.failureDetail))")
        #expect(matched.headingMatchesPage == true)
        #expect(matched.adding(warning: "w").headingMatchesPage == true)
        #expect(matched.observing("n").headingMatchesPage == true)

        let slipped = try finding(slip)
        #expect(slipped.version == "1.2.1", "\(String(describing: slipped.failureDetail))")
        #expect(slipped.headingMatchesPage == false)

        let untemplated = try finding(fixed)
        #expect(untemplated.version == "1.2.1", "\(String(describing: untemplated.failureDetail))")
        #expect(untemplated.headingMatchesPage == nil)
    }
}

/// Serves `<h1>VERSION</h1>` pages from the URL alone — no shared state, so
/// parallel tests cannot collide: `/match/<v>/` is headed `<v>`, anything else
/// `1.2.1`.
private final class HeadedPageStub: URLProtocol, @unchecked Sendable {
    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeadedPageStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stub.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let parts = url.pathComponents
        let heading = parts.count > 2 && parts[1] == "match" ? parts[2] : "1.2.1"
        let body = "<html><body><h1>\(heading)</h1><p>Fixed a crash.</p></body></html>"
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
