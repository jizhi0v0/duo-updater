# LibreWolf — channel verification record

Verified **2026-06-04** with `channel-verify` against an **installed cask**
(`brew install --cask librewolf`, then uninstalled). Single channel (stable).
Two recipe defects found and fixed; both were invisible without a real bundle.

| field | value |
|-------|-------|
| real bundle id | `net.librewolf.librewolf` (**not** `org.mozilla.librewolf`) |
| real short version | `151.0.3-1` |
| build version | `15126.6.2` |
| RemotingName | `librewolf` (Vendor=Mozilla) — irrelevant: single channel |
| detected channel | `stable` ✓ |
| VendorProbe (post-fix) | `151.0.3` → up to date (install `151.0.3-1` not newer) |
| full-chain winner (brew install) | Homebrew (cask has no `auto_updates`) |

## Defect 1 — wrong bundle id

Recipe keyed `org.mozilla.librewolf`. LibreWolf re-brands the Mozilla source and
ships as `net.librewolf.librewolf`, so the VendorProbe recipe **never matched**.
- A Homebrew install was silently rescued by `HomebrewCaskSource` (no
  `auto_updates` → brew wins the chain before VendorProbe is reached).
- A **direct download** from librewolf.net (no cask) would have fallen through to
  `.unknown` — undetected.

Fix: `bundleID: "net.librewolf.librewolf"`.

## Defect 2 — stale version endpoint (GitLab → Codeberg)

Recipe read `gitlab.com/api/v4/projects/44042130/repository/tags` (the
`librewolf-community/browser/bsys6` repo). That repo is **abandoned** — its newest
tag is `147.0.4-1` while current LibreWolf is `151.x`. So even with the bundle id
fixed, the probe reported `147.0.4` (masked as "up to date" only because
`147.0.4 < 151.0.3`; an older install would have been told to "update" to a stale
147 while 151 exists).

LibreWolf migrated to **Codeberg**. The brew cask's own livecheck confirms it:
`codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest` → `tag_name` =
`151.0.3-1`.

Fix:
- `url: "https://codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest"`
- `versionPattern: "tag_name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"` (captures `151.0.3`,
  drops the `-1` packaging suffix → not-newer vs `151.0.3-1` install → no phantom)
- `changelogURL: "https://codeberg.org/librewolf/bsys6/releases"`

## Tests updated
- `ChannelGuardTests.singleChannelRecipesResolve`: LibreWolf bundle id
  `org.mozilla.librewolf` → `net.librewolf.librewolf` (the live case was probing a
  bundle id no recipe matched — it passed vacuously and never exercised LibreWolf).
- `ChannelGuardTests.librewolfStripsPackagingSuffix`: offline body/pattern updated
  from the GitLab tags-array shape to the Codeberg `releases/latest` `tag_name`
  object shape, so the unit test mirrors the live recipe (`151.0.3-1` → `151.0.3`).

> Verified in the main working tree: with this fix folded in, the **full suite is
> green — 270 tests in 11 suites passed** (`librewolfStripsPackagingSuffix` and
> `singleChannelRecipesResolve` both meaningfully pass), and the live harness
> confirms the recipe answers `151.0.3` → up to date.

## Commands
```
swift run --package-path application-test channel-verify --check net.librewolf.librewolf --expect stable
swift run --package-path application-test channel-verify "/Applications/LibreWolf.app" --expect stable
```
