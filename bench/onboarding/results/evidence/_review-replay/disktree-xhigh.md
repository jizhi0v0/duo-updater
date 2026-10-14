**Blocking findings: 0**

I listed every group of installed copies before reading the rule. There is one bundle id, `io.github.tobi.disktree`, and it is the same in `packaging/macos/Info.plist.in` at v0.10.0 and v0.11.0. There is one edition, one stable track (all five releases are `prerelease: false` and `/releases/latest` returns v0.11.0), macOS versions 0.10.0, 0.10.1 and 0.11.0, aarch64 and x86_64 zips, no update feed in any version, and the same ad-hoc-unless-secrets workflow at v0.10.0 and v0.11.0. The single stable `.publishedDigestOnly` rule covers each group.

I traced these against the code and the GitHub API:
- **Version pattern.** Every listed tag (v0.9.0 to v0.11.0) is readable. Cargo semver rules out a two-part tag.
- **Unflagged rc tag.** The workflow publishes every `v*` tag with `--latest` and never flags a pre-release. A tag like `v0.12.0-rc.1` would produce a zip named `disktree-0.12.0-rc.1-aarch64-macos.zip`, which `^disktree-[0-9.]+-(?:aarch64|x86_64)-macos\.zip$` rejects. `resolve()` then falls back to the list and walks back to the newest release whose zip matches (`GitHubReleasesSource.swift:1605-1671`), so no wrong version is offered.
- **short == tag.** Settled from source: `xtask/src/bundle.rs` writes `CARGO_PKG_VERSION` into both `@VERSION@` placeholders, `xtask/Cargo.toml` has `version.workspace = true`, and `release.yml` refuses any tag that isn't `v<version>`.
- **Architecture markers.** `HostArch.isMarked` recognises both `aarch64` and `x86_64` at their boundaries.
- **Zip unpacking.** The installer extracts zips with `ditto -x -k`, which handles the `--sequesterRsrc` zips that `bundle.rs` makes.
- **Digests.** All four macOS digests quoted in the audit match the API's `digest` values.
- **Release notes.** The v0.11.0 body has 23 `What's Changed` items, as the audit says.
- **Test change.** Switching the check from `rc` to `-rc` still catches the only rc asset in the table, `Alacritty-v0.17.0-rc2.dmg`.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/io-github-tobi-disktree.swift:17-18`: "every published build so far is ad-hoc — no Team ID, `spctl` rejected". The audit inspected only 0.10.1 and 0.11.0, not 0.10.0. Whether a Developer ID was used depends on repository secrets the API can't show. If a build carries a Team ID, `SignatureVerifier.digestOnlyIdentity` takes the Team-ID gate or refuses with `teamIdentifierAppeared`. That makes a one-click fail, not a wrong install.
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/io-github-tobi-disktree.swift:18-19`: "with a seal that verifies and a signed identifier equal to the bundle id". If either is false for a release, gate 2 or `verifyDigestOnlyIdentity` (`infoPlistIdentifierMismatch`) refuses every one-click for that release.
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/io-github-tobi-disktree.swift:19-20`: "`disktree.app` at the top, no nested apps or helpers". `bundle.rs` (`ditto -c -k --sequesterRsrc --keepParent disktree.app`) supports this, but nobody listed the real zips' contents. If false, unpacking won't find the bundle.
- `docs/app-audits/io-github-tobi-disktree.md:65-68`: the downloaded zips' `shasum -a 256` "逐一相同" (each one matches) GitHub's digest. The API confirms the published digests and that they equal the audit's prefixes. The bytes actually served can't be checked here; if they differ, the digest gate refuses the install.

**Other unverified external claims**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/io-github-tobi-disktree.swift:8-9`: "the binary names no GitHub API or release address".
- `docs/app-audits/io-github-tobi-disktree.md:7-9`: `codesign -dvv` output `Signature=adhoc`, `TeamIdentifier=not set`, `spctl` rejected, `codesign --verify --deep --strict` exit 0.
- `docs/app-audits/io-github-tobi-disktree.md:13`: "没有 Homebrew cask（`brew info --cask disktree`: No Cask with this name exists）" (no Homebrew cask).
- `docs/app-audits/io-github-tobi-disktree.md:40`: each arch zip is a single slice (`lipo -archs`: `arm64` / `x86_64`).
- `docs/app-audits/io-github-tobi-disktree.md:52-53`: the channel-verify changelog output (`source structured: 1 entries; newest 0.11.0: 23 items, headings []`). The item count matches the release body; the parser output itself wasn't run.
- `docs/app-audits/io-github-tobi-disktree.md:24` and the PR description: channel-verify "GitHub wins, UPDATE -> 0.11.0 / up to date".
