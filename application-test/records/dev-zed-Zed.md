# Zed — channel verification record

Verified 2026-06-04. Preview = installed (`--scan`); Stable = official DMG mounted
read-only (not installed). Independent bundle ids (Pattern A).

| Channel | real bundle id | real short ver | detect() | update source → verdict |
|---------|----------------|----------------|----------|--------------------------|
| preview | `dev.zed.Zed-Preview` | `1.6.0` | preview ✓ | GitHub `zed-industries/zed` prerelease `v1.6.0-pre` = installed |
| stable  | `dev.zed.Zed`         | `1.5.3` | stable ✓  | **no update source** — VendorProbe miss; GitHub rule only covers preview |

## Notes
- `channel-verify`'s probe leg is VendorProbe-only; Zed Preview's source is the
  `GitHubReleaseRule` (prereleases of `zed-industries/zed`), confirmed live:
  newest prerelease `v1.6.0-pre` matches the installed Preview. detect()=preview ✓.
- **Confirmed coverage gap (known):** Zed **stable** detects correctly but has NO
  recipe — neither a VendorProbe nor a stable GitHub rule — so it can never see an
  update. The DMG (`dev.zed.Zed`, 1.5.3) mounts and classifies as stable, then the
  probe legitimately returns nothing. This matches the README's "⚠️ stable 版本检测缺口".
  → handoff: add a stable GitHubReleaseRule (non-prerelease tags `vX.Y.Z`) or a
  VendorProbe on `zed.dev/api/releases/stable/latest`.

## Commands
```
swift run --package-path application-test channel-verify --scan dev.zed.Zed-Preview --expect preview
swift run --package-path application-test channel-verify /tmp/zed-stable.dmg --expect stable
```
