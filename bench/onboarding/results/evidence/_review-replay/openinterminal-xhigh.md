**Blocking findings: 2**

1. `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/wang-jianing-app-OpenInTerminal.swift:22`: the version pattern accepts the Lite apps' `v1.x` tags. The asset filter only screens the version that gets offered. So whenever the source takes the list fallback this PR relies on, every Lite release on the page goes into OpenInTerminal's `releaseHistory` and is saved to the app's release timeline as an OpenInTerminal release.
   - Trigger: `/releases/latest` returns a Lite release. There are two ways this happens:
     - The vendor ships a Lite-only release. It has done so before: `1.1.5` (2020-09-25) has no matching full-app release. The audit's line 46 says otherwise ("Lite 与完整版一一配对发布"), but `1.1.5` is Lite-only and `v2.3.4` is full-only.
     - GitHub's tie-break picks the Lite release of a pair. Paired releases point at the same commit with the same `created_at`; for example, `v2.3.9` and `v1.2.8` are both `9351fcc…`, `2026-07-13T11:56:06Z`.

     In either case `settle` finds no `OpenInTerminal.zip` and swaps in `stableOnly(list)` (20 rows). It then builds `history` from every row whose tag matches `^v([0-9]+(?:\.[0-9]+)+)$`, with no asset check. That takes in `v1.2.8`, `v1.2.7`, …, `v1.2.0`: nine Lite releases on today's page. `AppListModel.recordReleaseTimeline` writes each one under OpenInTerminal's app id, with its date. `ReleaseTimelineStore.record` does not filter by version, and its "first sighting wins" dedupe means the entries are never removed. The PR's own fixture (`aLiteReleaseOnTopIsSkippedForTheFullAppsRelease`) follows this path and gets `releaseHistory == [1.2.8, 2.3.9]`. It checks only `displayVersion`, so the test passes anyway.
   - Evidence:
     - Recipe, lines 10–13: `The asset pattern is what keeps a Lite release from being read as this app's version` and `versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#`.
     - `GitHubReleasesSource.swift:1315-1316`: `if let list = try await fetchReleases(rule, list: true) { releases = Self.stableOnly(list) }`
     - `GitHubReleasesSource.swift:1330-1331`: `let history: [ReleaseHistoryEntry] = releases.compactMap { release in guard let v = VendorProbeRecipe.extractVersion(from: release.tag, pattern: rule.versionPattern)`. Nothing here checks the asset; the asset check only happens in the later walk at line 1344.
     - `App/Sources/AppListModel.swift:1990-1995`: `for entry in remote.releaseHistory { await releaseTimelineStore.record(appID: result.app.id, … version: entry.version, …`

2. `docs/app-audits/wang-jianing-app-OpenInTerminal.md:4`: the audit lists only `wang.jianing.app.OpenInTerminal`. Every full-app release through tag `2.0.5` (2019) shipped as `wang.jianing.OpenInTerminal`. The rule does not cover those copies, and the audit does not record them as a gap.
   - Trigger: take a copy of OpenInTerminal 2.0.5 (or older) that was not installed through Homebrew, for example one carried over by Migration Assistant. It is an x86_64 build that runs under Rosetta on an Apple Silicon Mac with macOS 15. Its `CFBundleIdentifier` is `wang.jianing.OpenInTerminal`. `GitHubReleasesSource` looks rules up only by bundle ID, so this rule never applies. The app has no `SUFeedURL`, and `HomebrewCaskSource` only answers when the cask is in the Caskroom. The copy therefore gets no detection, with no warning, even though 2.3.9 exists. The audit's "已知问题" lists only the Team change and the Lite apps. The rename is never mentioned.
   - Evidence:
     - GitHub API, `OpenInTerminal.xcodeproj/project.pbxproj` at `ref=2.0.5`: `PRODUCT_BUNDLE_IDENTIFIER = wang.jianing.OpenInTerminal;` (same at `2.0.1`).
     - At `ref=2.1.1` and later: `PRODUCT_BUNDLE_IDENTIFIER = wang.jianing.app.OpenInTerminal;`.
     - `OpenInTerminal/Info.plist` at `2.0.5`: `<key>CFBundleIdentifier</key> <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>`.
     - Rule: `bundleID: "wang.jianing.app.OpenInTerminal",` (recipe line 20).
     - `GitHubReleasesSource.swift:510`: `self.rules = Dictionary(grouping: rules, by: { $0.bundleID })`.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/wang-jianing-app-OpenInTerminal.swift:16` and `docs/app-audits/wang-jianing-app-OpenInTerminal.md:72-74`:
  - Claim: "One-click: Team C8VX3ZLX5U, notarized + stapled, from v2.3.9". The audit adds that the zip unpacks to `wang.jianing.app.OpenInTerminal` / `2.3.9`.
  - Partly confirmed: the zip's sha256 `14df8720…a387765` matches the asset `digest` the GitHub API reports.
  - Not confirmed: the signature, notarization and the bundle inside the zip.
  - If false: one-click is offered but refused, or installs a bundle whose version doesn't match.
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/wang-jianing-app-OpenInTerminal.swift:15` and `docs/app-audits/wang-jianing-app-OpenInTerminal.md:67-68`:
  - Claim: "universal" (`x86_64 arm64`).
  - If false: the asset name has no architecture marker, so `installableAsset` treats it as arch-neutral. An Intel-only build would then be one-click installed onto Apple Silicon.
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/wang-jianing-app-OpenInTerminal.swift:15`:
  - Claim: "short == tag", for the binary actually shipped.
  - Partly confirmed: `MARKETING_VERSION = 2.3.9` in the source at tag `v2.3.9`.
  - Not confirmed: the value in the shipped bundle.
  - If false: an up-to-date copy would be offered 2.3.9 forever. Older tags such as `2.0.5` (→ 2.0.4) and `2.2.3` (→ 2.2.2) did not match their tags.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:37`:
  - Claim: `/releases/latest` returns `v2.3.9`. Confirmed today.
  - Not confirmed: which release GitHub picks when two non-prerelease releases share the same commit and `created_at`. GitHub's tie-break isn't documented.
  - If it starts returning the Lite release: every check takes the list fallback and hits finding 1.

**Other unverified external claims**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/wang-jianing-app-OpenInTerminal.swift:17-18` and `docs/app-audits/wang-jianing-app-OpenInTerminal.md:5, 76-77`:
  - Claim: "v2.3.8 and earlier are signed by Team Q33U8R4U57".
  - The source doesn't settle this. `DEVELOPMENT_TEAM` is `Q33U8R4U57` from `2.1.1` through `v2.3.8`, but `C8VX3ZLX5U` at `2.0.1` and `2.0.5`.
  - Either way, the worst case is a refused install.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:75`: v2.3.8 is "Notarized Developer ID，stapled".
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:78-79`:
  - Claim: `build-signed.sh` was "2026-07-14 新增" and "v2.3.9 是第一个用它出的包".
  - The API shows a conflict: v2.3.9 was published on `2026-07-13T12:08:34Z`, and the tree of the commit it tags (`9351fcc…`, shared with `v1.2.8`) contains only `build-unsigned.sh`.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:56`: `LSMinimumSystemVersion` = `10.13` in the shipped v2.3.8 and v2.3.9 bundles.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:8, 53`: there is no Sparkle or update framework in the bundle, and `strings` finds no update endpoint.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:9-10`: the Homebrew cask `openinterminal` is not `auto_updates`.
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md:91-96`: the `channel-verify` / `feed-discover` outputs quoted under "如何复验".
