# HBuilderX — channel verification record

Verified 2026-06-04 with `channel-verify --scan` against **both installed bundles**.
Stable and Alpha are **independent bundle ids** (different .app, different id) — a
clean Pattern A family, both covered by VendorProbe recipes.

| Channel | real bundle id | real short ver | detect() | VendorProbe → verdict |
|---------|----------------|----------------|----------|------------------------|
| stable  | `io.dcloud.HBuilderX`      | `5.07.2026041006`       | stable ✓ | 5.07.2026041006 = installed, up to date |
| alpha   | `io.dcloud.HBuilderXAlpha` | `5.11.2026052520-alpha` | alpha ✓  | 5.11.2026052520-alpha = installed, up to date |

## Notes
- Alpha's bundle id is `io.dcloud.HBuilderXAlpha` (installed as `HBuilderX-Alpha.app`),
  distinct from stable's `io.dcloud.HBuilderX` — so the channel split is fully
  observable from the bundle id; no preference reading needed.
- Both VendorProbe recipes answered with the installed version → no phantom update.

## Commands
```
swift run --package-path application-test channel-verify --scan io.dcloud.HBuilderX --expect stable
swift run --package-path application-test channel-verify --scan io.dcloud.HBuilderXAlpha --expect alpha
```
