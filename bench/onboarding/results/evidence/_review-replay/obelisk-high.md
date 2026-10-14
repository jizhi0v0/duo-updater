I didn't write the review file. The write to `.claude-review/review.md` was refused because permission wasn't granted, so the full review is below. If you approve the write, I can save it there.

---

**Blocking findings: 0**

I listed the groups of installed copies before reading the rules, then checked each one against the code and the GitHub API:

- **0.2.4–0.2.5** (Team 433DLLA855, `SUFeedURL`): `SparkleAppcastSource` answers them. It comes before `GitHubReleasesSource` in `SourceStack.make`.
- **0.1.0, 0.2.0, 0.2.1, 0.2.2** (ad-hoc, no feed): the new detection-only rule covers them.
  - Every one of these used bundle ID `com.obelisk.app`. I checked `app/package.json` at v0.2.0 and v0.2.5, and at commit `b7506ee765` for 0.1.0, because the v0.1.0 tag contains no app source.
  - No rename happened.
- **Tag `v0.2.3`** has no release, so there are no shipped copies.
- **rc tracks**: the vendor's `release-app.yml` adds `--prerelease` for any `-` tag. None has been published yet, and the audit records this as a gap.

The audit gives a reason for not using `.publishedDigestOnly` on the ad-hoc copies, and it holds. `SignatureVerifier.digestOnlyIdentity` returns `.teamAppeared` when the download has a Team ID and the installed copy doesn't, and `verifyDigestOnlyIdentity` then throws. So an ad-hoc → Developer ID swap is refused on both routes.

The rule's pattern `^v([0-9]+(?:\.[0-9]+)+)$` is anchored. It reads all six published tags, accepts two-part tags and rejects an unflagged `-rc` tag. The rule uses `/releases/latest` (`usePrereleases = false` in the golden). Every release has a mac asset.

On the changelog side:
- The `.gitHubReleases` decoder drops prereleases when `channel` is nil.
- `skipSections` match whole headings, case-insensitively (`GitHubMarkdownParser.isSkipped`).
- The vendor's `update-release.mjs` really does write a single `<item>` with a plain `<description>` and no `sparkle:format`.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-obelisk-app.swift:45`: "From 0.2.4 the bundle declares `SUFeedURL` and `SparkleAppcastSource` … answers (with the EdDSA-signed zip as the one-click route)". If the shipped 0.2.4/0.2.5 bundles don't declare that feed, or the EdDSA signature doesn't verify, those copies fall through to the detection-only GitHub rule and lose one-click without any error.
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-obelisk-app.swift:47`: "The 0.2.2 bundle declares no feed and is ad-hoc signed with no Team ID". Earlier builds are inferred to be the same from the vendor's notes. If any of them is actually signed with Team 433DLLA855, the rule names no install asset, so those copies get detection without the one-click install they could have.
- `docs/app-audits/com-obelisk-app.md:29`: the 0.2.4/0.2.5 dmg and zip are Team `433DLLA855` and `Notarized Developer ID`. If the next release changes Team ID, the Sparkle install route's Team gate refuses it.

**Other unverified external claims**

- `docs/app-audits/com-obelisk-app.md:9`: "0.2.2 是 ad-hoc 签名、无 Team（`Signature=adhoc`，`codesign --verify` 失败）"
- `docs/app-audits/com-obelisk-app.md:12`: Sparkle 2.9.4 driven through `electron-sparkle-updater`, with `SUVerifyUpdateBeforeExtraction=true` and `SUAutomaticallyUpdate=false`, and an `electron-updater` fallback via the bundled `app-update.yml`.
- `docs/app-audits/com-obelisk-app.md:47`: the 302 from the feed URL to `releases/download/v0.2.5/appcast-arm64.xml`, and the per-arch enclosure names.
- `docs/app-audits/com-obelisk-app.md:62`: both feeds carry only `minimumSystemVersion 12.0`, and the bundle's `LSMinimumSystemVersion` = `12.0`.
- `docs/app-audits/com-obelisk-app.md:84`: the `channel-verify` outputs ("6 entries; newest 0.2.5: 23 items …", "raw inline notes, 6385 chars"), and "清空 `skipSections` 后两条测试变红（已实测）".
- `docs/app-audits/com-obelisk-app.md:110`: the sha512 matches `latest-mac.yml`, and `openssl pkeyutl -verify` prints "Signature Verified Successfully".
- `docs/app-audits/com-obelisk-app.md:113`: the bundle contains only four `Obelisk Helper*.app` and no `LoginItems`.
- `docs/app-audits/com-obelisk-app.md:133`: the `channel-verify` results table for the 0.2.5 / 0.2.4 / 0.2.2 dmgs.