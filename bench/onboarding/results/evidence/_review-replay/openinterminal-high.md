**Blocking findings: 2**

1. `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/wang-jianing-app-OpenInTerminal.swift:20`: copies installed under the app's pre-rename bundle ID `wang.jianing.OpenInTerminal` are neither covered by a rule nor recorded as a gap, so they silently get no update detection.
   - Trigger: a user who installed OpenInTerminal 2.0.x or earlier from the GitHub release zip (not brew) and still has it, e.g. migrated onto an Apple Silicon Mac running macOS 15+, where the 2019 Intel build runs under Rosetta. Its `CFBundleIdentifier` is `wang.jianing.OpenInTerminal`. No rule in the registry matches that ID (the only `wang.jianing` entry in the repo is this rule), so the row gets no GitHub answer, and the user is never told that 2.3.9 exists. The audit never mentions the rename. It says it read bundle IDs from `master` only (`docs/app-audits/wang-jianing-app-OpenInTerminal.md:11`: "签名、打包、资产名读自仓库 `master` 分支源码"), lists one bundle ID (line 4), and its 已知问题 section (lines 83-85) records only the Team ID change and the Lite apps.
   - Evidence: the recipe has a single rule, `bundleID: "wang.jianing.app.OpenInTerminal"`. The vendor's source via the GitHub API shows the rename between tags 2.0.5 (2019-08-26) and 2.1.1 (2020-01-08):
     - `contents/OpenInTerminal.xcodeproj/project.pbxproj?ref=2.0.5` → `PRODUCT_BUNDLE_IDENTIFIER = wang.jianing.OpenInTerminal`
     - `?ref=2.0.1` → `PRODUCT_BUNDLE_IDENTIFIER = wang.jianing.OpenInTerminal`
     - `?ref=2.1.1`, `?ref=2.2.3` and `?ref=v2.3.0` → `PRODUCT_BUNDLE_IDENTIFIER = wang.jianing.app.OpenInTerminal`

     Releases 0.9.1 through 2.0.5 carry `OpenInTerminal.app.zip` and are still published (`/releases?per_page=100`).

2. `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/wang-jianing-app-OpenInTerminal.swift:22`: on the list fallback that this PR exists to handle, the Lite apps' v1.x releases are written into OpenInTerminal's release timeline as releases of this app. The recipe comment and the audit say the asset pattern keeps Lite releases out, but it only does that for the offered version.
   - Trigger: `/releases/latest` returns a Lite release (the scenario that `aLiteReleaseOnTopIsSkippedForTheFullAppsRelease` fixtures). `settle` falls back to `releases = Self.stableOnly(list)` with a page of 20 that interleaves the two products. It then builds `releaseHistory` from every release whose tag matches `^v([0-9]+(?:\.[0-9]+)+)$`, with no asset check. Lite tags `v1.2.8`, `v1.2.7`, `v1.2.6`, … all match. `AppListModel` records each history entry into `releaseTimelineStore` under OpenInTerminal's app ID, and `ReleaseTimelineStore.record` does no version filtering. The result is persisted "OpenInTerminal 1.2.8 / 1.2.7 / …" release events with the Lite publish dates, and they also count toward `ReleaseStats`.
   - Evidence:
     - `GitHubReleasesSource.swift:1316`: `releases = Self.stableOnly(list)`
     - `GitHubReleasesSource.swift:1330-1331`: `let history: [ReleaseHistoryEntry] = releases.compactMap { release in guard let v = VendorProbeRecipe.extractVersion(from: release.tag, pattern: rule.versionPattern)` (the asset filter only applies later, in the `for release in releases` walk at 1344)
     - `App/Sources/AppListModel.swift:1990-1995`: `for entry in remote.releaseHistory { await releaseTimelineStore.record(appID: result.app.id, … version: entry.version, …`
     - The recipe comment at lines 10-13: "The asset pattern is what keeps a Lite release from being read as this app's version". This is false for the history that the same resolution returns.
     - In the test fixture (`OpenInTerminalGitHubRuleTests.swift`), the list is `[lite, full]`, so `remote.releaseHistory` there contains `1.2.8`. The test never asserts on it.

**Unverified external claims the behavior depends on**

- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:5` and the recipe comment at `wang-jianing-app-OpenInTerminal.swift:16-18`: "v2.3.9 起 Team `C8VX3ZLX5U`; v2.3.8 及更早是 `Q33U8R4U57`". One-click from v2.3.9 onward depends on future releases keeping `C8VX3ZLX5U`. If v2.3.9 is not actually signed by that Team, every one-click install is refused.
- `wang-jianing-app-OpenInTerminal.swift:15`: "universal". If the zip were Intel-only, `isArchIncompatibleOnly` handling could differ. The asset name carries no arch, so the source treats it as installable on any host.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:41` / the PR description: "/releases/latest can land on a Lite release". The API today returns `v2.3.9` (`created_at 2026-07-13T11:56:06Z`). Finding 2 only fires when this happens.
- Finding 1 assumes the 2.0.x (old bundle ID) builds still launch on Apple Silicon with macOS 15+ under Rosetta. I did not check this.

**Other unverified external claims**

- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:72-75`: v2.3.9 passes `codesign --verify --deep --strict`, `spctl` reports Notarized Developer ID, and it is stapled. v2.3.8 is notarized and stapled. (The zip digest `sha256:14df8720…a387765` does match the GitHub API asset digest.)
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:56`: `LSMinimumSystemVersion` = `10.13` for v2.3.8 and v2.3.9.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:7` / `:38-40`: `CFBundleVersion` is a constant `1`, and `MARKETING_VERSION = 2.3.9` on `master`.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:8`: no `SUFeedURL`, no Sparkle.framework, and no update endpoint in the binary.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:45`: the Lite-on-top test "reads 1.2.8 when the asset pattern is removed (verified red)".
