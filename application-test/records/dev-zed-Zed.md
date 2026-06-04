# Zed — channel verification record

Verified 2026-06-04. Preview = installed (`--scan`); Stable = official DMG mounted
read-only (not installed). Independent bundle ids (Pattern A).

| Channel | real bundle id | real short ver | detect() | update source → verdict |
|---------|----------------|----------------|----------|--------------------------|
| preview | `dev.zed.Zed-Preview` | `1.6.0` | preview ✓ | GitHub `zed-industries/zed` prerelease `v1.6.0-pre` = installed |
| stable  | `dev.zed.Zed`         | `1.5.3` | stable ✓  | GitHub `zed-industries/zed` `/releases/latest` `v1.5.3` = installed (rule added in 收尾) |

## 2026-06-04 收尾 — gap closed + Preview regression fixed

- **Stable gap closed**: added `GitHubReleaseRule(dev.zed.Zed, zed-industries/zed)`
  (default `usePrereleases:false` → `/releases/latest`, which excludes prereleases →
  `v1.5.3`; default pattern strips `v`). Live API confirms latest `v1.5.3` = the
  mounted stable DMG's version. Detection-only (Zed self-updates). Offline lock:
  `GitHubReleaseRuleTests.zedStableRuleExtractsVPrefixedTag`.
- **Preview regression found by full-chain `--check`**: re-running the *full
  production chain* (not just `--scan`) on the installed Preview first returned
  `status=unknown (no source answered)`. Root cause: the Preview `GitHubReleaseRule`
  never declared `channel`, so it defaulted to `.stable`; Codex's later channel gate
  (`rule.channel == app.releaseChannel`) then refused it for the `.preview` install.
  The earlier "preview verified" used `--scan` (detect-only) + a manual live-API
  check, which never exercised the gate. Fix: `channel: .preview` on the rule; lock:
  `…zedStableRuleExtractsVPrefixedTag` asserts `rule("dev.zed.Zed-Preview").channel == .preview`.
- **Post-fix `--check dev.zed.Zed-Preview`**: detected=preview, winning source=GitHub,
  latest=`1.6.0`=installed, status=**up to date**. ✓

## Notes
- `channel-verify`'s probe leg is VendorProbe-only; Zed Preview's source is the
  `GitHubReleaseRule` (prereleases of `zed-industries/zed`), confirmed live:
  newest prerelease `v1.6.0-pre` matches the installed Preview. detect()=preview ✓.
- ~~**Confirmed coverage gap (known):** Zed **stable** has NO recipe~~ — **resolved
  2026-06-04 收尾**: stable GitHubReleaseRule added (see section above). The DMG
  (`dev.zed.Zed`, 1.5.3) classifies as stable and now resolves via GitHub `/releases/latest`.

## Commands
```
swift run --package-path application-test channel-verify --scan dev.zed.Zed-Preview --expect preview
# full production chain (catches channel-gate issues --scan misses):
swift run --package-path application-test channel-verify --check dev.zed.Zed-Preview --expect preview
swift run --package-path application-test channel-verify /tmp/zed-stable.dmg --expect stable
```
