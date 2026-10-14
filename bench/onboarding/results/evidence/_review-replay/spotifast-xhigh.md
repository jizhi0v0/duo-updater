**Blocking findings: 1**

1. `docs/app-audits/rocks-spotifast-Spotifast.md:87-90`: Pre-rename Fastpotify copies (`me.paolino.fastpotify`, 0.1.0–0.9.1, which also covers every `-rcN` build) get no update detection. The audit records this only as an open `BundleIDMigration` decision. That entry would not cover these copies, because the GitHub source never reads it. So under REVIEW.md this group is neither covered nor recorded with a reason that holds.
   - Trigger: a user has Fastpotify 0.9.1 installed (bundle id `me.paolino.fastpotify`, Team `JPL7999US3`; this is the audit's own measurement, line 101). No source answers for that copy:
     - no Sparkle feed;
     - no official cask (audit line 9);
     - no vendor probe;
     - `GitHubReleasesSource` returns nil because no rule is keyed on that id.
     So DuoUpdater shows no update for the copy, even though `crmne/spotifast` `/releases/latest` is v0.13.1 (checked through the API, published 2026-10-14). Next step 2 in the audit (line 113) tells a maintainer to add the bounds it lists as a `BundleIDMigration` entry. If they do, the copy is still not detected. `BundleIDMigration` re-files an old-id copy only for vendor probes and changelog recipes, through `InstalledApp.recipeBundleID`. The GitHub source looks rules up by the on-disk id. The audit gives one reason for not adding the entry: upstream dropped its own old-id handling (commit e10a8d4a6; checked through the API). That explains why an upgrade starts a fresh profile, not why the copies can't be covered. And the decision is explicitly left open ("留给维护者决定"). The 0.4.0/0.5.0 rc builds are in this same group, because they predate 0.10.0. The audit's channel table (line 30) instead lists them under "同 id".
   - Evidence:
     - `docs/app-audits/rocks-spotifast-Spotifast.md:88-90`: "规则只按新 id 注册，所以旧 id 副本不会被检测到；没有加 `BundleIDMigration`。… 要不要为旧 id 加迁移条目留给维护者决定"
     - `docs/app-audits/rocks-spotifast-Spotifast.md:113-114`: "决定是否为 `me.paolino.fastpotify` → `rocks.spotifast.Spotifast`（Team `JPL7999US3`，lastFrom `0.9.1`，firstTo `0.10.0`）加 `BundleIDMigration` 条目"
     - `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/GitHubReleasesSource.swift:651-652`: `guard let bundleID = app.bundleID, let candidates = rules[bundleID] else { return nil  // no rule for this app — not applicable`
     - `DuoUpdaterCore/Sources/DuoUpdaterCore/Models/BundleIDMigration.swift:8-9`: "`InstalledApp.recipeBundleID` files an old-id copy under the new id, so vendor probes and changelog recipes find it." `recipeBundleID` is read only in `ChangelogRecipeSelection.swift:9` and `VendorProbeSource.swift:223,345`; `GitHubReleasesSource` does not read it.
     - `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/rocks-spotifast-Spotifast.swift:27-29`: "0.9.1 and older ship as `me.paolino.fastpotify` …, which this rule does not claim — see the audit."

Other groups I checked, all covered or not applicable:

- **`rocks.spotifast.Spotifast` 0.10.0–0.13.1:** covered.
  - Every non-prerelease tag from v0.1.0 to v0.13.1 is `vX.Y.Z` and is read by `^v([0-9]+(?:\.[0-9]+)+)$`. Two-part tags also match. An unflagged `-rc` tag is refused rather than misread.
  - Every rc tag is flagged `prerelease: true`.
  - `spotifast-v0.13.1-macos-universal.dmg` matches `installAssetPattern`.
- **Other macOS editions:** there are none. Each release has a single universal dmg.
- **Update feed:** there is no Sparkle feed in any range.
- **Signing:** the worst case of a signer difference is a refused install, which REVIEW.md excludes.
- **Changelog recipe:**
  - `.gitHubReleases` with `channel` nil keeps only non-prerelease rows (`StructuredChangelogDecoder.swift:835-840`).
  - Every stable body from v0.2.0 on has `## Thanks`.
  - The CRLF bodies (v0.2.0, v0.8.0) still split cleanly, because the parser uses `components(separatedBy: .newlines)`.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/rocks-spotifast-Spotifast.swift:31-32`: "One-click: Team JPL7999US3 on 0.12.0 and 0.13.0, notarized dmg, one executable and no nested apps or helpers". This was not checked for v0.13.1, the release one-click would install today. If the signer or the bundle layout differs, the one-click install is refused, or the swap leaves helpers behind.
- `docs/app-audits/rocks-spotifast-Spotifast.md:59`: the upstream updater "只在用户点「Restart to update」时才 handoff 给 helper 换包 … 没有「退出时自动换入已暂存构建」这一步". The audit itself says this was read from source and not tested. If it is false, a build the vendor updater staged earlier could replace the version DuoUpdater installed.
- `docs/app-audits/rocks-spotifast-Spotifast.md:40`: "short `0.13.0` ↔ build `0.13.0` … 真包上两者相等". The vendor's `packaging/macos/Info.plist` fills them from separate placeholders (`__VERSION__` and `__BUILD__`). Equality was observed only on real dmgs. If the short version ever stops equalling the tag, the comparison against the tag is wrong.

**Other unverified external claims**

- `docs/app-audits/rocks-spotifast-Spotifast.md:9`: "官方 homebrew-cask 没有 `spotifast` / `fastpotify`".
- `docs/app-audits/rocks-spotifast-Spotifast.md:70`: the observed `channel-verify` output "19 entries; newest 0.13.0: 42 items".
- `docs/app-audits/rocks-spotifast-Spotifast.md:82`: "v0.13.0 dmg 下载后 `shasum -a 256` = `7c16925e…a93c`，与资产 `digest` 一致".
- `docs/app-audits/rocks-spotifast-Spotifast.md:100-101`: the 0.10.0 and 0.9.1 dmgs report `rocks.spotifast.Spotifast` and `me.paolino.fastpotify` respectively, both from the same Team.
