// Bench grader for the `fix-*` cases (cases/fix-*.json). Copied into the
// agent's clone after the run, it reads that clone's recipes through the
// production paths: `ChangelogService.loadDiagnostic` against the LIVE vendor
// pages, and `VendorProbeSource.probeDiagnostic` against a stub serving the
// Trim Enabler feed (the regression test from #1295, kept as a hidden test).
// It writes facts only; `score-fix.py` turns them into pass/fail.
import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite(.serialized) struct ZZFixGrade {
    private static var out: URL? {
        ProcessInfo.processInfo.environment["BENCH_FIX_OUT"].map(URL.init(fileURLWithPath:))
    }
    private static var caseName: String { ProcessInfo.processInfo.environment["BENCH_FIX_CASE"] ?? "" }

    private static func describe(_ d: ChangelogService.ChangelogDiagnostic?) -> [String: Any] {
        guard let d else { return ["recipe": false] }
        let entries = d.changelog?.entries ?? []
        return [
            "recipe": true,
            "resolvedURL": d.resolvedURL.absoluteString,
            "httpStatus": d.httpStatus as Any,
            "fetchFailed": d.fetchFailed,
            "entries": entries.count,
            "first": entries.first.map { e in
                ["version": e.version, "date": e.date ?? "", "items": e.items.count,
                 "sample": Array(e.items.prefix(3))] as [String: Any]
            } as Any,
        ]
    }

    private static func changelog(_ bundleID: String, _ channel: ReleaseChannel?, _ version: String?) async -> [String: Any] {
        guard let recipe = ChangelogRecipeRegistry.recipe(forBundleID: bundleID, channel: channel, version: version)
        else { return ["recipe": false] }
        var row = describe(await ChangelogService.loadDiagnostic(recipe, version: version, feedPage: nil))
        row["version"] = version ?? ""
        return row
    }

    /// No cache: the recipe revalidates its own fetch of the same manifest, and a
    /// copy `URLCache.shared` kept from an earlier grade would compare it against
    /// an older version.
    private static func liveJSON(_ url: String) async -> [String: Any]? {
        var request = URLRequest(url: URL(string: url)!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    @Test func grade() async throws {
        guard let out = Self.out else { return }
        var facts: [String: Any] = ["case": Self.caseName]
        switch Self.caseName {
        case "fix-longbridge":
            facts["stable-1.0.0"] = await Self.changelog("com.longbridge.app.desktop", .stable, "1.0.0")
            facts["stable-0.20.1"] = await Self.changelog("com.longbridge.app.desktop", .stable, "0.20.1")
            let manifest = await Self.liveJSON(
                "https://assets.lbkrs.com/github/release/longbridge-desktop/preview/latest.json")
            let previewVersion = manifest?["version"] as? String
            facts["previewManifestVersion"] = previewVersion ?? ""
            facts["preview-current"] = await Self.changelog(
                "com.longbridge.app.desktop.preview", .preview, previewVersion)
        case "fix-qoder":
            facts["qoder"] = await Self.changelog("com.qoder.ide", nil, nil)
            let latest = await Self.liveJSON(
                "https://center.qoder.sh/algo/api/update/darwin-arm64/stable/latest?machineId=00000000-0000-4000-8000-000000000000")
            facts["qoderEndpointVersion"] = latest?["productVersion"] as? String ?? ""
            let qoder = ChangelogRecipeRegistry.recipe(forBundleID: "com.qoder.ide")
            facts["acknowledgedStaleEntry"] = qoder?.acknowledgedStaleEntry ?? ""
            // What the recipe reads with, wherever in the source it was edited: the
            // pattern is assembled from statics in ChangelogRecipe.swift, so a diff
            // can bend it without naming it.
            facts["qoderRecipe"] = qoder.map { r -> [String: Any] in
                ["entryPattern": r.entryPattern, "itemPatterns": r.itemPatterns,
                 "source": r.source.absoluteString, "sourceTemplate": r.sourceTemplate ?? "",
                 "maxEntries": r.maxEntries ?? -1, "minItemLength": r.minItemLength]
            } ?? [:]
        case "fix-trim":
            facts["trimProbe"] = await Self.trimHidden()
            facts["trimChangelog"] = await Self.changelog("org.cindori.TrimEnabler4", nil, "4.3.6")
        default:
            facts["error"] = "unknown case"
        }
        let data = try JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: out)
    }

    /// #1295's regression test, as facts: the feed's first two items, verbatim.
    private static func trimHidden() async -> [String: Any] {
        let feed = #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        	<channel>
        		<title>Trim Enabler</title>
        		<link></link>
        		<description></description>
        		<language>en</language>
        		<item>
        			<title>26</title>
        			<sparkle:minimumSystemVersion>10.9</sparkle:minimumSystemVersion>
        			<sparkle:releaseNotesLink>https://updates.devmate.com/releasenotes/26/org.cindori.TrimEnabler4.html</sparkle:releaseNotesLink>
        			<sparkle:releaseNotesLink xml:lang="en">https://updates.devmate.com/releasenotes/26/org.cindori.TrimEnabler4.html</sparkle:releaseNotesLink>
        			<pubDate>Sat, 02 Jan 2021 12:27:37 +0000</pubDate>
        			<enclosure url="https://dl.devmate.com/org.cindori.TrimEnabler4/26/1609590590/TrimEnabler-26.zip" length="63924802" type="application/octet-stream" sparkle:version="26" sparkle:shortVersionString="4.3.6"/>
        			<sparkle:deltas>
        				<enclosure url="https://dl.devmate.com/org.cindori.TrimEnabler4/26/1609590590/21.delta" sparkle:version="26" sparkle:shortVersionString="4.3.6" sparkle:deltaFrom="21" length="244256" type="application/octet-stream"/>
        				<enclosure url="https://dl.devmate.com/org.cindori.TrimEnabler4/26/1609590590/24.delta" sparkle:version="26" sparkle:shortVersionString="4.3.6" sparkle:deltaFrom="24" length="243660" type="application/octet-stream"/>
        				<enclosure url="https://dl.devmate.com/org.cindori.TrimEnabler4/26/1609590590/25.delta" sparkle:version="26" sparkle:shortVersionString="4.3.6" sparkle:deltaFrom="25" length="138424" type="application/octet-stream"/>
        			</sparkle:deltas>
        		</item>
        		<item>
        			<title>25</title>
        			<sparkle:minimumSystemVersion>10.9</sparkle:minimumSystemVersion>
        			<sparkle:releaseNotesLink>https://updates.devmate.com/releasenotes/25/org.cindori.TrimEnabler4.html</sparkle:releaseNotesLink>
        			<sparkle:releaseNotesLink xml:lang="en">https://updates.devmate.com/releasenotes/25/org.cindori.TrimEnabler4.html</sparkle:releaseNotesLink>
        			<pubDate>Wed, 11 Nov 2020 14:33:06 +0000</pubDate>
        			<enclosure url="https://dl.devmate.com/org.cindori.TrimEnabler4/25/1605105283/TrimEnabler-25.zip" length="64037173" type="application/octet-stream" sparkle:version="25" sparkle:shortVersionString="4.3.5"/>
        			<sparkle:deltas>
        				<enclosure url="https://dl.devmate.com/org.cindori.TrimEnabler4/25/1605105283/20.delta" sparkle:version="25" sparkle:shortVersionString="4.3.5" sparkle:deltaFrom="20" length="211288" type="application/octet-stream"/>
        				<enclosure url="https://dl.devmate.com/org.cindori.TrimEnabler4/25/1605105283/21.delta" sparkle:version="25" sparkle:shortVersionString="4.3.5" sparkle:deltaFrom="21" length="199240" type="application/octet-stream"/>
        				<enclosure url="https://dl.devmate.com/org.cindori.TrimEnabler4/25/1605105283/24.delta" sparkle:version="25" sparkle:shortVersionString="4.3.5" sparkle:deltaFrom="24" length="197001" type="application/octet-stream"/>
        			</sparkle:deltas>
        		</item>
        	</channel>
        </rss>
        """#
        guard let recipe = VendorProbeRegistry.recipes.first(where: { $0.bundleID == "org.cindori.TrimEnabler4" }),
              let server = try? RecipeVerificationTests.StubServer(body: feed)
        else { return ["recipe": false] }
        defer { server.stop() }
        let outcome = await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
        return [
            "recipe": true,
            "failure": outcome.failure.map { "\($0)" } ?? "",
            "shortVersion": outcome.remote?.shortVersion ?? "",
            "publishedAt": outcome.remote?.publishedAt?.timeIntervalSince1970 ?? 0,
            "downloadURL": outcome.remote?.downloadURL?.absoluteString ?? "",
            "warnings": outcome.warnings.map { "\($0)" },
        ]
    }
}
