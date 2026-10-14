**Blocking findings: 1**

1. `docs/app-audits/com-lokii-app.md:84`: the "how to re-verify" section gives the wrong SHA-256 for `v0.1.2/Lokii-arm64.dmg` and says it matches the API digest, but the API contradicts it.
   - Trigger: someone follows 「如何复验」, runs `shasum -a 256` on the current `v0.1.2/Lokii-arm64.dmg` and compares it with the doc. The real hash ends in `…dc8b29`, so it won't match the doc's `…db8b29`. They would conclude the asset changed or was tampered with, or that the digest-only proof is broken, when nothing is wrong.
   - Evidence: the audit says
     `# 下载并核 sha256（与 API digest 一致）:` (line 83) and
     `#   v0.1.2/Lokii-arm64.dmg   ff475bae…db8b29` (line 84).
     `GET repos/huangy7/lokii/releases` returns this for `v0.1.2` / `Lokii-arm64.dmg`:
     `"digest": "sha256:ff475baeb6e91693f7de11c0e2e9293cb1cde4246495a07f3680b7adfddc8b29"`. Its last six characters are `dc8b29`, not `db8b29`. The other four fragments on lines 84–86 match the API: `…78db3c`, `…ca71bd`, `…342593` and `…ef2924`. The recipe takes the digest from the API at runtime, not from this doc, so detection and install are not affected.

What I checked and found sound. Every group of installed copies is covered by the rule:
- **Every published release.** `com.lokii.app` stable v0.1.0, v0.1.1 and v0.1.2 are all non-prerelease and not drafts, and `/releases/latest` returns `v0.1.2`. `scripts/build.sh` sets `bundle_id="com.lokii.app"` and stamps the Cargo version into `CFBundleShortVersionString` at both `v0.1.0` and `v0.1.2`, so there was no rename.
- **Both architectures.** Every release ships exactly `Lokii-arm64.dmg` and `Lokii-x86_64.dmg`. `HostArch` tokens pick the arm64 asset on Apple silicon. An x86_64 copy is offered arm64, which Gate 5b allows.
- **Copies from the vendor's tap.** `Casks/l/lokii.rb` returns 404 in Homebrew/homebrew-cask, so these copies fall through `HomebrewCaskSource` to the GitHub rule.
- **Ad-hoc signing.** It is handled by `.publishedDigestOnly`. If a future Developer ID build appears, the route refuses it via `digestOnlyIdentity` → `.teamAppeared`, which matches the audit's next-steps note.
- **Version pattern.** `^v([0-9]+(?:\.[0-9]+)+)$` reads `v0.2.0` and `v0.2`, and rejects an unflagged `v0.2.0-rc.1`.
- **Workflow claims in the recipe comment hold.** The release workflow refuses a tag that is not `v` + the crate version, uses the placeholder `--notes`, and always runs `--latest`.
- **AppUpdater claim holds.** `AppUpdater.swift` reads `/releases/latest` and opens the dmg URL.
- **Tests and golden are consistent with the rule.** The golden matches darktable's apart from the rule's own fields. The new `multiCandidateCases` entry satisfies `multiCandidatePatternsAreAllCovered`, and the `DigestOnlyRecipeTests` key set and picks are consistent with the rule.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-lokii-app.swift:17-20`: "both per-arch dmgs are ad-hoc (no Team ID, not notarized), with a sealed signature that passes `codesign --verify --deep --strict` and the signed identifier `com.lokii.app` (0.1.1 and 0.1.2)". `verifyDigestOnlyIdentity` needs four things: an ad-hoc flag, `signedID == "com.lokii.app"`, the Info.plist bundle ID equal to the rule's, and `CFBundleShortVersionString` equal to the tag without `v`. If any is false for the shipped bundles, the one-click install that is offered is refused at the signature gate. If a build carries a Team ID, the route refuses it as `teamIdentifierAppeared`.
- `docs/app-audits/com-lokii-app.md:69`: "真实下载的 `shasum -a 256` 全部一致" (the API digests match the bytes GitHub serves). Digest-only trust rests on this. If it is false, every install fails at `verifyPublishedDigest`.
- `docs/app-audits/com-lokii-app.md:4` / PR description: "CI has no signing secrets". `release.yml` signs with Developer ID whenever `APPLE_CERTIFICATE`/`LOKII_SIGN_IDENTITY` are set. Repository secrets can't be read through the API, so whether the next release stays ad-hoc can't be checked. If it does not, the digest-only route refuses it, as the audit's next-steps note says.

**Other unverified external claims**

- `docs/app-audits/com-lokii-app.md:65`: "`Sealed Resources version=2 files=4`" and "`codesign --verify --deep --strict` 退出 0". These are local `codesign` observations on the 0.1.1 and 0.1.2 bundles.
- `docs/app-audits/com-lokii-app.md:4`: "`spctl` rejected，无 stapled ticket".
- `docs/app-audits/com-lokii-app.md:5`: "`CFBundleVersion` 恒为 `1`". This is consistent with `build_number="$(git -C … rev-list --count HEAD …)"` under a shallow `actions/checkout@v4`, but the shipped plists were not checked here.
- `docs/app-audits/com-lokii-app.md:52`: "官网 `lokii.huangy.top` 只有下载链接".
- `docs/app-audits/com-lokii-app.md:76-77`: "ad-hoc 签名的 designated requirement 绑定在单个构建的 cdhash 上（TN3127），所以每次换包后 TCC 视其为新 app，需要重新授予 Full Disk Access".
- `docs/app-audits/com-lokii-app.md:93-98` / PR description: channel-verify results. These are "up to date" on the 0.1.2 arm64 dmg and "UPDATE → 0.1.2" on the 0.1.1 arm64 and x86_64 dmgs, from local runs.
- PR description: "all six downloads matched it". The audit lists only five hashes; the v0.1.0 `Lokii-x86_64.dmg` (API digest `483685fd…18856a`) is not shown.
