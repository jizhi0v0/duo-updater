**Blocking findings: 0**

I checked the rule against all 27 vendor releases from the GitHub API (fetched 2026-10-14): every non-prerelease tag from `v1.0.0` to `v4.0.0` is `vX.Y.Z` and is read by `^v([0-9]+(?:\.[0-9]+)+)$`. Every release has exactly one asset, `Secretive.zip`. The digests for v4.0.0 (`877517e2…c1fa`) and v3.0.4 (`696d0781…84ba`) match the audit. `/releases/latest` returns `v4.0.0`.

I also listed the groups of installed copies:

- **Stable copies of every version:** covered. `release.yml` on `main` and at `v2.4.1` both stamp the tag minus `v` into `CI_VERSION`, and `Info.plist` maps that to `CFBundleShortVersionString`. The bundle ID was already `com.maxgoedjen.Secretive.Host` at `v2.4.1`.
- **Copies on a `_beta` track:** covered. They read as `.stable`. `4.0.0` does not compare as newer than `4.1.0_beta1`, and `4.1.0` does, so a beta copy is offered only its own final release.
- **Nightly copies (`0.0.0_nightly-<date>`):** recorded as a gap in both the audit and `CHANNEL_COVERAGE_TODO.md`. I confirmed the audit's description from source:
  - `nightly.yml` stamps that version string.
  - `ReleaseChannel.detect` only recognises `-nightly` as a dash-separated tail, so a nightly copy reads as `.stable`.
  - `VersionComparator` reports 4.0.0 as newer than the nightly.
  - The vendor's own `Updater.evaluate` also offers 4.0.0 to a nightly, because `SemVer("0.0.0_nightly-…")` parses to `[0,0,0]`. That supports the recorded decision.

The changelog fixture is consistent with the real v4.0.0 body, and the min-OS install gate the recipe comment relies on exists in `VendorInstaller` / `SignatureVerifier`.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-maxgoedjen-Secretive-Host.swift:15`: "Team Z72PRUAWF6, notarized (not stapled)". If a future `Secretive.zip` is signed by another team or is not notarized, the installer's trust gates refuse the one-click install.
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-maxgoedjen-Secretive-Host.swift:13`: "Nightlies (`0.0.0_nightly-<date>`) are Actions artifacts only, never a Release". `nightly.yml` on `main` confirms it today. If the vendor starts publishing nightlies as Releases with that tag shape, the anchored pattern returns no version for them.

**Other unverified external claims**

- `docs/app-audits/com-maxgoedjen-Secretive-Host.md:84`: the package checks on v4.0.0: "`codesign --verify --deep --strict` 通过，`spctl` → `accepted / Notarized Developer ID`，未 staple" (passes `codesign --verify --deep --strict`; `spctl` reports `accepted / Notarized Developer ID`; not stapled), and the same for v3.0.4. The audit also says the archive has no `._*` entries.
- `docs/app-audits/com-maxgoedjen-Secretive-Host.md:62`: the real packages declare `LSMinimumSystemVersion` `15.0` (4.0.0) and `14.0` (3.0.4), and are universal (`x86_64 arm64 arm64e`).
- `docs/app-audits/com-maxgoedjen-Secretive-Host.md:95`: "厂商自己的 updater 对 nightly 也会显示这个更新（以「test build」样式，不发通知）" (the vendor's own updater also shows this update to a nightly, styled as a "test build", with no notification). The update being offered is confirmed from `Updater.swift`; the "test build" styling and no-notification behaviour were not checked.
- `docs/app-audits/com-maxgoedjen-Secretive-Host.md:104-107`: the local `channel-verify` / `feed-discover` results ("winning source GitHub", "UPDATE → 4.0.0" for 3.0.4).
- `CHANNEL_COVERAGE_TODO.md:275` / `docs/app-audits/com-maxgoedjen-Secretive-Host.md:39`: nightly artifacts "需登录 GitHub 才能下载" (need a GitHub login to download).
