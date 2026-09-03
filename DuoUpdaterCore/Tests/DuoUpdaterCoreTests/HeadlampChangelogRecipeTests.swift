import Testing
import Foundation
@testable import DuoUpdaterCore

/// Headlamp is the app `GitHubMarkdownParser`'s own doc comment names as the
/// reason it refuses Markdown tables — so the shared `.gitHubReleases` decoder
/// can never render these notes, and this recipe reads the release JSON with
/// regexes instead. Three things have to hold, and each has already gone wrong
/// somewhere in this registry:
///   - the table era (0.42.0+) yields the change cell and NOT the attribution
///     cell, the alignment row, or the image-only header row;
///   - the bullet era (0.41.0 and older, all still on the endpoint) still
///     yields items, via the second pattern;
///   - the repo's other tag families (`headlamp-helm-*`) are not read as
///     releases of this app.
///
/// Fixture: three release objects from
/// `api.github.com/repos/kubernetes-sigs/headlamp/releases` (fetched
/// 2026-09-03), bodies trimmed to one section each.
@Suite struct HeadlampChangelogRecipeTests {

    private func changelog() throws -> Changelog {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.microsoft.Headlamp"))
        return try #require(
            ChangelogExtractor.extract(from: headlampReleasesFixture, using: recipe))
    }

    @Test func readsTheTableEraAndDropsTheAttributionColumn() throws {
        let entries = try changelog().entries
        let newest = try #require(entries.first)
        #expect(newest.version == "0.45.0")
        #expect(newest.date == "2026-08-20")
        #expect(newest.items.count == 4)
        #expect(newest.items.first == "Plugin i18n now fetches only the active locale's "
            + "translation file instead of all declared locales, preventing a flood of 404 "
            + "requests when a plugin declares multiple languages.")
        // The second cell is credit, not a change.
        #expect(!newest.items.contains { $0.contains("Thanks to") })
        // The alignment row and the image-only header row are not changes either.
        #expect(!newest.items.contains { $0.hasPrefix(":-") || $0.isEmpty })
    }

    /// `\"Unreachable\"` in the raw JSON must reach the reader as a quoted word,
    /// not as backslash-quote — the escape trap `.json` recipes exist around.
    @Test func jsonEscapesAreDecoded() throws {
        let items = try changelog().entries.flatMap(\.items)
        #expect(items.contains { $0.contains("fails with \"Unreachable\" on clusters") })
        #expect(!items.contains { $0.contains("\\\"") })
    }

    /// Inline code survives as its text: the cell says `` `setInterval` `` and a
    /// plain-text renderer would otherwise print the backticks.
    @Test func inlineCodeIsUnwrapped() throws {
        let items = try changelog().entries.flatMap(\.items)
        #expect(items.contains { $0.contains("the manual setInterval in useClustersVersion") })
    }

    @Test func theOlderBulletReleasesStillYieldItems() throws {
        let entries = try changelog().entries
        let older = try #require(entries.first { $0.version == "0.43.0" })
        #expect(older.items.count == 2)
        #expect(older.items.first?.hasPrefix("Added opt-in service account token auth") == true)
    }

    @Test func theHelmChartTagIsNotAReleaseOfThisApp() throws {
        let entries = try changelog().entries
        #expect(entries.map(\.version) == ["0.45.0", "0.43.0"])
        #expect(!entries.contains { $0.version.contains("helm") })
    }

    /// `api.github.com` serves this same document both compact and
    /// pretty-printed — which one arrives varied by request on 2026-09-03, and a
    /// pattern written against one form reads as a dead recipe against the other
    /// (`duo verify` caught exactly that, against fixture tests that were green).
    /// Both fixtures below are the same three releases, re-serialized; the parse
    /// must not be able to tell them apart.
    @Test func bothJSONFormattingsParseTheSame() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "com.microsoft.Headlamp"))
        #expect(ChangelogExtractor.extract(from: headlampReleasesPrettyFixture, using: recipe)
            == ChangelogExtractor.extract(from: headlampReleasesFixture, using: recipe))
    }

}

private let headlampReleasesFixture = #"""
[{"tag_name":"v0.45.0","name":"0.45.0","draft":false,"prerelease":false,"created_at":"2026-08-20T23:53:30Z","published_at":"2026-08-20T23:55:46Z","assets":[{"name":"checksums.txt"}],"body":"Headlamp 0.45.0 reduces desktop startup memory and unnecessary background requests, while adding new scheduling and Gateway API views, guided resource creation forms, and more flexible plugin and product customization. Security updates protect desktop APIs, verify external plugin archives, and close command-consent and dependency vulnerabilities. Accessibility improvements make high-zoom layouts, keyboard controls, and custom theme contrast more usable, alongside 31 bug fixes across authentication, port forwarding, Resource Map, tables, and the desktop app.\r\n\r\n## ⚡ Performance\r\n\r\n| <img src=\"https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/docs/images/icon.png\" width=\"800\" height=\"0\" alt=\"\"> | <img src=\"https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/docs/images/icon.png\" width=\"200\" height=\"0\" alt=\"\"> |\r\n|:--|--:|\r\n| Plugin i18n now fetches only the active locale's translation file instead of all declared locales, preventing a flood of 404 requests when a plugin declares multiple languages. | Thanks to:<br>@YousufFFFF<br>@r0hansaxena.<br>Thanks to @mjeanrichard for reporting.<br>#7363 |\r\n| Desktop startup now defers optional work, retains smaller Kubernetes objects, and tunes garbage collection, reducing memory by about 60 MiB RSS across combined isolated measurements. | Thanks to @illume.<br>#7358 |\r\n| Replaced the manual `setInterval` in `useClustersVersion` with React Query's `useQueries`, so polling pauses when the browser tab is hidden and unnecessary network requests to connected clusters are avoided. | Thanks to:<br>@shreyas-acharya<br>@illume.<br>#6707 |\r\n\r\n## 🐞 Bug fixes (part 1)\r\n\r\n| <img src=\"https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/docs/images/icon.png\" width=\"800\" height=\"0\" alt=\"\"> | <img src=\"https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/docs/images/icon.png\" width=\"200\" height=\"0\" alt=\"\"> |\r\n|:--|--:|\r\n| Fixed a broken context lookup key in the port-forward handler so that port forwarding no longer fails with \"Unreachable\" on clusters affected by the regression introduced in 0.43. | Thanks to:<br>@r0hansaxena<br>@illume.<br>Thanks to @rforced for reporting.<br>#6109 |\r\n"},{"tag_name":"headlamp-helm-0.45.0","name":"headlamp-helm-0.45.0","draft":false,"prerelease":false,"created_at":"2026-08-20T23:58:48Z","published_at":"2026-08-20T23:59:14Z","assets":[{"name":"headlamp-0.45.0.tgz"}],"body":"Headlamp is an easy-to-use and extensible Kubernetes web UI."},{"tag_name":"v0.43.0","name":"0.43.0","draft":false,"prerelease":false,"created_at":"2026-06-16T22:36:50Z","published_at":"2026-06-16T22:41:58Z","assets":[{"name":"checksums.txt"}],"body":"## ✨ Enhancements\r\n\r\n- Added opt-in service account token auth for in-cluster deployments, enabling Headlamp to work behind OIDC or other external auth proxies. Thanks to @0xMH and @unixpariah. Also thanks to @yolossn for reporting the issue.\r\n- Helm chart probes now support a configurable scheme (HTTP/HTTPS) and full timing settings, enabling correct probe behavior when backend TLS is enabled. Thanks to @gambtho. Also thanks to @mbasha86 for reporting the issue."}]
"""#

/// The same three releases as above, as this endpoint also serves them.
private let headlampReleasesPrettyFixture = #"""
[
  {
    "tag_name": "v0.45.0",
    "name": "0.45.0",
    "draft": false,
    "prerelease": false,
    "created_at": "2026-08-20T23:53:30Z",
    "published_at": "2026-08-20T23:55:46Z",
    "assets": [
      {
        "name": "checksums.txt"
      }
    ],
    "body": "Headlamp 0.45.0 reduces desktop startup memory and unnecessary background requests, while adding new scheduling and Gateway API views, guided resource creation forms, and more flexible plugin and product customization. Security updates protect desktop APIs, verify external plugin archives, and close command-consent and dependency vulnerabilities. Accessibility improvements make high-zoom layouts, keyboard controls, and custom theme contrast more usable, alongside 31 bug fixes across authentication, port forwarding, Resource Map, tables, and the desktop app.\r\n\r\n## ⚡ Performance\r\n\r\n| <img src=\"https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/docs/images/icon.png\" width=\"800\" height=\"0\" alt=\"\"> | <img src=\"https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/docs/images/icon.png\" width=\"200\" height=\"0\" alt=\"\"> |\r\n|:--|--:|\r\n| Plugin i18n now fetches only the active locale's translation file instead of all declared locales, preventing a flood of 404 requests when a plugin declares multiple languages. | Thanks to:<br>@YousufFFFF<br>@r0hansaxena.<br>Thanks to @mjeanrichard for reporting.<br>#7363 |\r\n| Desktop startup now defers optional work, retains smaller Kubernetes objects, and tunes garbage collection, reducing memory by about 60 MiB RSS across combined isolated measurements. | Thanks to @illume.<br>#7358 |\r\n| Replaced the manual `setInterval` in `useClustersVersion` with React Query's `useQueries`, so polling pauses when the browser tab is hidden and unnecessary network requests to connected clusters are avoided. | Thanks to:<br>@shreyas-acharya<br>@illume.<br>#6707 |\r\n\r\n## 🐞 Bug fixes (part 1)\r\n\r\n| <img src=\"https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/docs/images/icon.png\" width=\"800\" height=\"0\" alt=\"\"> | <img src=\"https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/docs/images/icon.png\" width=\"200\" height=\"0\" alt=\"\"> |\r\n|:--|--:|\r\n| Fixed a broken context lookup key in the port-forward handler so that port forwarding no longer fails with \"Unreachable\" on clusters affected by the regression introduced in 0.43. | Thanks to:<br>@r0hansaxena<br>@illume.<br>Thanks to @rforced for reporting.<br>#6109 |\r\n"
  },
  {
    "tag_name": "headlamp-helm-0.45.0",
    "name": "headlamp-helm-0.45.0",
    "draft": false,
    "prerelease": false,
    "created_at": "2026-08-20T23:58:48Z",
    "published_at": "2026-08-20T23:59:14Z",
    "assets": [
      {
        "name": "headlamp-0.45.0.tgz"
      }
    ],
    "body": "Headlamp is an easy-to-use and extensible Kubernetes web UI."
  },
  {
    "tag_name": "v0.43.0",
    "name": "0.43.0",
    "draft": false,
    "prerelease": false,
    "created_at": "2026-06-16T22:36:50Z",
    "published_at": "2026-06-16T22:41:58Z",
    "assets": [
      {
        "name": "checksums.txt"
      }
    ],
    "body": "## ✨ Enhancements\r\n\r\n- Added opt-in service account token auth for in-cluster deployments, enabling Headlamp to work behind OIDC or other external auth proxies. Thanks to @0xMH and @unixpariah. Also thanks to @yolossn for reporting the issue.\r\n- Helm chart probes now support a configurable scheme (HTTP/HTTPS) and full timing settings, enabling correct probe behavior when backend TLS is enabled. Thanks to @gambtho. Also thanks to @mbasha86 for reporting the issue."
  }
]
"""#
