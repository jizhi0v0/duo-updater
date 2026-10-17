import Testing
import Foundation
@testable import DuoUpdaterCore

/// Benchmark grader. Copied into a clone AFTER the onboarding agent has finished,
/// so the agent never sees it. Opt-in: does nothing without BENCH_GRADE_CASE.
///
/// It asks the PRODUCTION code what the clone's registry does for one app:
/// - the full source chain (`UpdateChecker` over `SourceStack.make`) for a copy at
///   `oldVersion` and one at the newest version, as the menu bar would;
/// - which changelog the workbench pane would show (same order as channel-verify);
/// - `GitHubReleaseRule.installableAsset` for each of the newest releases, on an
///   Apple-silicon Mac and on an Intel Mac, so Intel selection is graded too.
/// The same file runs on main for the reference answer; the two JSONs are diffed.
struct ZZBenchGrade {

    struct Case: Decodable {
        let bundleID: String
        let owner: String
        let repo: String
        let oldVersion: String
        let newVersion: String
        /// Extra grade cases that test channel detection (Loop's `🧪` dev build, Zettlr's
        /// `+nightly`): give the synthesized copy the channel production's scan would,
        /// from its version string, instead of `.stable`.
        let detectChannel: Bool?
    }

    struct Asset { let name: String; let url: URL; let size: Int64? }
    struct Rel { let tag: String; let prerelease: Bool; let assets: [Asset] }

    static func releases(_ c: Case, token: String?) async throws -> [Rel] {
        var req = URLRequest(url: URL(string:
            "https://api.github.com/repos/\(c.owner)/\(c.repo)/releases?per_page=15")!)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return arr.filter { ($0["draft"] as? Bool) != true }.map { r in
            Rel(tag: r["tag_name"] as? String ?? "",
                prerelease: r["prerelease"] as? Bool ?? false,
                assets: (r["assets"] as? [[String: Any]] ?? []).compactMap { a in
                    guard let n = a["name"] as? String,
                          let u = (a["browser_download_url"] as? String).flatMap(URL.init(string:))
                    else { return nil }
                    return Asset(name: n, url: u, size: (a["size"] as? NSNumber)?.int64Value)
                })
        }
    }

    static func describe(_ log: Changelog) -> [String: Any] {
        guard let newest = log.entries.first else { return ["entries": 0] }
        let headings: [String]
        if let markdown = newest.markdown {
            headings = ChangelogMarkdown.blocks(from: markdown).compactMap { block in
                if case .heading = block.kind { return String(block.text.characters) }
                return nil
            }
        } else {
            headings = newest.content.compactMap { block -> String? in
                if case .heading(let h) = block { return h }
                return nil
            }
        }
        return ["entries": log.entries.count, "newestVersion": newest.version,
                "newestItems": newest.items.count, "headings": headings,
                "markdown": newest.markdown != nil]
    }

    static func chain(_ c: Case, version: String, token: String?) async -> [String: Any] {
        let app = InstalledApp(
            name: c.repo, bundleID: c.bundleID, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/nonexistent/ZZBench-\(c.repo).app"),
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: c.detectChannel == true
                ? ReleaseChannel.detect(name: c.repo, bundleID: c.bundleID, keystoneChannel: nil, version: version)
                : .stable)
        let checker = UpdateChecker(sources: SourceStack.make(githubToken: token), toolbox: ToolboxSource())
        let r = await checker.check(app)
        let status: String
        switch r.status {
        case .upToDate: status = "upToDate"
        case .updateAvailable(let v): status = "update→\(v)"
        case .unknown: status = "unknown"
        case let other: status = "\(other)"
        }
        var pane: [String: Any] = [:]
        if let recipe = ChangelogRecipeSelection.recipe(for: r) {
            let log = await ChangelogService.loadUncached(
                recipe, version: ChangelogRecipeSelection.targetVersion(for: r),
                feedPage: ChangelogRecipeSelection.feedPage(for: r, recipe: recipe))
            pane = ["kind": "recipe", "recipeID": recipe.recipeID]
            if let log { pane.merge(describe(log)) { $1 } } else { pane["failed"] = true }
        } else if let log = r.remote?.structuredChangelog {
            pane = ["kind": "sourceStructured"].merging(describe(log)) { $1 }
        } else if let html = r.remote?.releaseNotesHTML {
            pane = ["kind": "rawInline", "chars": html.count]
        } else {
            pane = ["kind": "webOrNone"]
        }
        return [
            "channel": app.releaseChannel.rawValue,
            "status": status,
            "source": r.remote?.sourceName ?? "<none>",
            "latest": r.remote?.displayVersion ?? "<none>",
            "download": r.remote?.downloadURL?.lastPathComponent ?? "<nil>",
            "oneClickKind": r.remote?.vendorInstallerKind.map { "\($0)" } ?? "<none>",
            "requiresManualInstaller": r.remote?.requiresManualInstaller ?? true,
            "installTrust": r.remote.map { "\($0.installTrust)" } ?? "<nil>",
            "changelogPane": pane,
        ]
    }

    @Test func grade() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let casePath = env["BENCH_GRADE_CASE"], let outPath = env["BENCH_GRADE_OUT"] else { return }
        let c = try JSONDecoder().decode(Case.self, from: Data(contentsOf: URL(fileURLWithPath: casePath)))
        let token = await GitHubToken.resolve()

        let slug = "\(c.owner)/\(c.repo)".lowercased()
        let rules = GitHubReleaseRegistry.rules.filter {
            $0.bundleID == c.bundleID || "\($0.owner)/\($0.repo)".lowercased() == slug
        }
        let ruleDump: [[String: Any]] = rules.map { r in [
            "bundleID": r.bundleID, "slug": "\(r.owner)/\(r.repo)", "channel": r.channel.rawValue,
            "usePrereleases": r.usePrereleases, "versionPattern": r.versionPattern,
            "installAssetPattern": r.installAssetPattern ?? "<nil>",
            "installerKind": r.installerKind.map { "\($0)" } ?? "<nil>",
            "installTrust": "\(r.installTrust)",
        ] }
        let changelogRecipes = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == c.bundleID }.map(\.recipeID)

        // Asset selection per release, per host. Only the rules on this bundle id
        // and the stable channel, as production would consult for a stable copy.
        var perRelease: [[String: Any]] = []
        let rels = try await Self.releases(c, token: token)
        for rel in rels.prefix(8) {
            var row: [String: Any] = ["tag": rel.tag, "prerelease": rel.prerelease]
            for rule in rules where rule.bundleID == c.bundleID && rule.channel == .stable {
                let a = rel.assets.map { (name: $0.name, url: $0.url, size: $0.size) }
                let pat = rule.installAssetPattern
                let arm = pat.flatMap { GitHubReleaseRule.installableAsset(
                    from: a, matching: $0, preferring: .arm64, allowingIntelTranslation: true) }
                let intel = pat.flatMap { GitHubReleaseRule.installableAsset(
                    from: a, matching: $0, preferring: .x86_64, allowingIntelTranslation: false) }
                let v = VendorProbeRecipe.extractVersion(from: rel.tag, pattern: rule.versionPattern)
                row["version"] = v ?? "<no match>"
                row["arm64"] = arm?.url.lastPathComponent ?? "<none>"
                row["x86_64"] = intel?.url.lastPathComponent ?? "<none>"
            }
            perRelease.append(row)
        }

        let out: [String: Any] = [
            "rules": ruleDump,
            "changelogRecipes": changelogRecipes,
            "old": await Self.chain(c, version: c.oldVersion, token: token),
            "new": await Self.chain(c, version: c.newVersion, token: token),
            "perRelease": perRelease,
        ]
        let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: outPath))
    }
}
