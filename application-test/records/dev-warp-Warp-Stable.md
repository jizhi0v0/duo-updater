# Warp — channel verification record

Verified 2026-06-04. Stable = installed (`--scan`); Preview + Dev = official DMGs
mounted read-only (not installed). Independent bundle ids (Pattern A); one
`channel_versions.json` lists every channel's date-version.

| Channel | real bundle id | real short ver | detect() | VendorProbe → verdict |
|---------|----------------|----------------|----------|------------------------|
| stable  | `dev.warp.Warp-Stable`  | `0.2026.05.27.15.44.01` | stable ✓  | 0.2026.05.27.15.44 = installed, up to date |
| preview | `dev.warp.Warp-Preview` | `0.2026.05.27.15.44.01` | preview ✓ | 0.2026.05.27.15.44 = dmg, up to date |
| dev     | `dev.warp.Warp-Dev`     | `0.2026.06.04.09.31.00` | dev ✓     | 0.2026.06.04.09.31 = dmg, up to date |

## Notes
- Channel reads cleanly from the hyphen-suffixed bundle id (`Warp-Preview`/`Warp-Dev`).
- All three recipes answer; the probe strips the trailing `.NN` so the from→to compares
  cleanly against the install. Detection-only (Warp self-updates).
- `beta` / `canary` tracks are abandoned by Warp and intentionally NOT given recipes
  (the JSON still lists stale versions; a recipe there would phantom-update forever).

## Commands
```
swift run --package-path application-test channel-verify --scan dev.warp.Warp-Stable --expect stable
swift run --package-path application-test channel-verify /tmp/WarpPreview.dmg --expect preview
swift run --package-path application-test channel-verify /tmp/WarpDev.dmg     --expect dev
```
