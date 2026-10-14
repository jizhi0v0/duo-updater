**Blocking findings: 0**

I listed every group of installed copies before reading the rules, then checked how each one is handled:

- **0.2.4 and 0.2.5, arm64 and x64, with `SUFeedURL`:** Sparkle handles them. `SourceStack.make` puts `SparkleAppcastSource` ahead of `GitHubReleasesSource`, and the vendor's `release-app.yml` on `main` asserts that `SUFeedURL`, `SUPublicEDKey` and `SUVerifyUpdateBeforeExtraction` are present in every build.
- **0.1.0, 0.2.0, 0.2.1 and 0.2.2, ad-hoc and without a feed:** the new detection-only rule covers them.
  - `appId` is `com.obelisk.app` in `app/package.json` at `v0.2.0` and at commit `b7506ee`, which precedes `v0.1.0`. There is no rename.
  - All six release tags match `^v([0-9]+(?:\.[0-9]+)+)$`.
  - The workflow rejects tags that aren't `X.Y.Z[-suffix]` and publishes `-` tags with `--prerelease`. Both `/releases/latest` and the anchored pattern exclude rc tags.
  - The reason for not naming an install asset holds. Through the gate (`SignatureVerifier.verifyTeamIdentifierMatch`), an ad-hoc copy throws `noTeamIdentifier`. Through the `.publishedDigestOnly` route, `digestOnlyIdentity` returns `.teamAppeared` and the install throws. Both refuse an ad-hoc → Developer ID swap.
- **Future rc copies:** none exist yet, and the audit records them as a gap.

For the changelog recipe:

- I fetched all six live release bodies. Every non-change `##` section they contain is matched by `skipSections`; the parser matches a whole heading, case-insensitively. The roster and download lists drop out.
- The test fixture's item counts add up: v0.2.5 gives 4 + 5 + 5 + 6 + 3 = 23 items, and v0.2.1 gives 6 + 8 + 5 + 5 = 24.
- With `skipSections` emptied, `dropsTheRosterAndTheDownloadList` would fail.
- `decodeGitHubReleases` drops prereleases on the stable channel.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-obelisk-app.swift:46`: "The 0.2.2 bundle declares no feed … the vendor's notes say the same of every earlier build". Only the 0.2.2 package was mounted (audit, "如何复验"). For 0.1.0, 0.2.0 and 0.2.1 I confirmed the bundle ID only from `app/package.json` in the source, not from the shipped binaries.
  - If one of those builds carried a different `CFBundleIdentifier`, its copies would get no detection.
  - If one declared a dead `SUFeedURL`, Sparkle would throw and the loop would still reach this rule, so that case is harmless.

**Other unverified external claims**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-obelisk-app.swift:46`: "The 0.2.2 bundle declares no feed and is ad-hoc signed with no Team ID".
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-obelisk-app.swift:44`: "From 0.2.4 the bundle declares `SUFeedURL` and `SparkleAppcastSource` … answers (with the EdDSA-signed zip as the one-click route)". The vendor's workflow on `main` asserts the `SUFeedURL`. The 0.2.4 binary and the EdDSA verification were checked only locally by the author.
- `docs/app-audits/com-obelisk-app.md:8`: "Team ID: `433DLLA855`（0.2.4、0.2.5 的 dmg 与 zip 均为此 Team，`spctl` = `Notarized Developer ID`）".
- `docs/app-audits/com-obelisk-app.md:47`: "2026-10-14 该地址 302 到 `releases/download/v0.2.5/appcast-arm64.xml`", and that the arm64 and x64 feeds each name their own architecture's zip.
- `docs/app-audits/com-obelisk-app.md:60`: "两份 feed 都只有 `<sparkle:minimumSystemVersion>12.0`，**没有** `maximumSystemVersion`；真包 `LSMinimumSystemVersion` = `12.0`".
- `docs/app-audits/com-obelisk-app.md:69`: "2026-10-14 两份 appcast 均无 `<sparkle:deltas>`".
- `docs/app-audits/com-obelisk-app.md:78`, `:84`: the `channel-verify` output "6 entries; newest 0.2.5: 23 items …", and that without the recipe the pane shows "raw inline notes, 6385 chars, no structure".
- `docs/app-audits/com-obelisk-app.md:110`: "0.2.5 arm64 zip 的 sha512 与 `latest-mac.yml` 一致", and that the `sparkle:edSignature` verifies against `SUPublicEDKey`, which is the same in 0.2.4 and 0.2.5.
- `docs/app-audits/com-obelisk-app.md:14`, `:39`: the `electron-updater` fallback that runs "原生桥加载失败时", and the ADR-0015 quote "The initial channel is stable".
