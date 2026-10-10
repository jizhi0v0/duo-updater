import Foundation
import Testing

@testable import DuoUpdaterCore

/// Three releases from `api.github.com/repos/robinebers/openusage/releases`
/// (fetched 2026-10-10): v0.7.14 whole, v0.7.14-beta.1 and v0.7.13 trimmed by
/// whole lines to their first two items. The beta is `prerelease: true`.
private let openUsageReleasesFixture = #"""
[
 {
  "tag_name": "v0.7.14",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-10-06T04:19:59Z",
  "body": "## v0.7.14\n\n### New Features\n- Refresh and save tokens for independent Codex homes (#1322) by @robinebers.\n- Add Report an Issue to the Options menu (#1343) by @robinebers.\n\n### Bug Fixes\n- Keep the panel’s top edge steady during height animations (#1345) by @kennnyq.\n- Preserve each screen’s header and footer during navigation (#1346) by @kennnyq.\n- Restore Codex local spending for multiple accounts (#1349) by @robinebers.\n- Show OpenCode session reset countdowns below 1% usage by @hasan007-sudo.\n- Prefer structured Cursor team usage pools (#1337) by @robinebers.\n- Keep slow Codex history scans from blocking live quota (#1338) by @robinebers.\n- Update Codex plan names and preserve header labels (#1332) by @validatedev.\n\n### Chores\n- Update PostHog to 3.85.3 (#1347) by @app/dependabot.\n- Record the beta changelog by @robinebers.\n\n**Full Changelog**:\nhttps://github.com/robinebers/openusage/compare/v0.7.13...v0.7.14\n"
 },
 {
  "tag_name": "v0.7.14-beta.1",
  "prerelease": true,
  "draft": false,
  "published_at": "2026-10-04T14:23:21Z",
  "body": "## v0.7.14-beta.1\n\n### New Features\n- feat(codex): refresh and persist tokens for independent Codex homes on account cards ([#1322](https://github.com/robinebers/openusage/pull/1322)) by @robinebers\n- feat: add Report an Issue to the Options menu ([#1343](https://github.com/robinebers/openusage/pull/1343)) by @robinebers"
 },
 {
  "tag_name": "v0.7.13",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-10-02T02:48:31Z",
  "body": "## v0.7.13\n\n### New Features\n- feat(codex): one card per account across Codex homes and pi logins (read-only) ([#1321](https://github.com/robinebers/openusage/pull/1321)) by @robinebers\n- feat(codex): price Ultrafast and GPT-6 Sol models ([#1327](https://github.com/robinebers/openusage/pull/1327)) by @robinebers"
 }
]
"""#

@Suite struct OpenUsageChangelogRecipeTests {

    private let bundleID = "com.robinebers.openusage"

    private func parsed(_ channel: ReleaseChannel) throws -> Changelog {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: bundleID, channel: channel))
        #expect(recipe.channel == channel)
        return try #require(ChangelogService.parse(recipe, body: openUsageReleasesFixture))
    }

    @Test func stableReadsStableReleasesOnly() throws {
        let entries = try parsed(.stable).entries
        #expect(entries.map(\.version) == ["0.7.14", "0.7.13"])
        let newest = try #require(entries.first)
        #expect(newest.date == "2026-10-06")
        #expect(newest.items.first == "Refresh and save tokens for independent Codex homes (#1322) by @robinebers.")
        // The `**Full Changelog**:` line and the compare link under it are not changes.
        #expect(!newest.items.contains { $0.contains("compare/") })
    }

    /// A beta install is offered the default channel too (Sparkle), so the beta
    /// rail keeps the stable release that graduates.
    @Test func betaReadsBothTrains() throws {
        let entries = try parsed(.beta).entries
        #expect(entries.map(\.version) == ["0.7.14", "0.7.14-beta.1", "0.7.13"])
        #expect(entries[1].date == "2026-10-04")
        #expect(entries[1].items.count == 2)
    }
}
