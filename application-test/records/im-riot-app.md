# Element — channel verification record

Verified 2026-06-04 with `channel-verify` against the **official zips of both
channels** (extracted, `.app` inspected; not installed). Independent bundle ids
(Pattern A).

> **This run caught a shipped bug.** The Nightly recipe was keyed to
> `io.element.nightly` — a bundle id **no real build has**. The real Nightly bundle
> is `im.riot.nightly`. The probe silently missed on every real Nightly install, and
> the unit test passed only because it asserted against the *same* wrong id. Fixed
> 2026-06-04 (`VendorProbeRecipe.swift` + `ChannelGuardTests.swift`), then re-verified
> green below. Classic "a feed/guess is not the app" trap.

| Channel | real bundle id | real short ver | detect() | VendorProbe → verdict |
|---------|----------------|----------------|----------|------------------------|
| stable  | `im.riot.app`     | `1.12.20`    | stable ✓  | 1.12.20 = build, up to date |
| nightly | `im.riot.nightly` | `2026060401` | nightly ✓ | 2026060401 = build, up to date (after fix) |

## Notes
- Nightly's version is a `YYYYMMDDNN` build stamp; stable is semver. Both recipes
  read `currentRelease` from the per-channel `releases.json`.
- Detection-only (Element self-updates via Squirrel).

## Commands
```
swift run --package-path application-test channel-verify "/tmp/Element.app"         --expect stable
swift run --package-path application-test channel-verify "/tmp/Element Nightly.app" --expect nightly
```
