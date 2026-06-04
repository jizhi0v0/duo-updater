# Thunderbird — channel verification record

Verified 2026-06-04 with `channel-verify` against **real bundles** (stable =
installed; beta/esr/nightly = official DMGs mounted read-only, not installed).
Re-verified after the RemotingName fix — all four channels now route correctly.

Authoritative channel marker: `Contents/Resources/application.ini` → `RemotingName`
(per-channel, readable without launching). The product-details JSON's `…b3`/`…esr`
suffixes do **not** survive into the installed `CFBundleShortVersionString`.

| Channel | real bundle id | real short ver | `RemotingName` | detect() | probe → verdict |
|---------|----------------|----------------|----------------|----------|-----------------|
| stable  | `org.mozilla.thunderbird`       | `151.0.1` | `thunderbird`         | stable ✓  | 151.0.1, up to date |
| beta    | `org.mozilla.thunderbirdbeta`   | `152.0`   | `thunderbird-beta`    | beta ✓    | 152.0b3 (pre-release, up to date) |
| esr     | `org.mozilla.thunderbird`       | `140.11.1`| `thunderbird-esr`     | esr ✓     | 140.11.1esr (= install, up to date) |
| nightly | `org.mozilla.thunderbird-daily` | `153.0a1` | `thunderbird-nightly` | nightly ✓ | 153.0a1, up to date |

## Fix applied (2026-06-04)
1. `ReleaseChannel.detect()` gained a highest-priority `mozillaRemotingName` signal;
   `AppScanner` reads it from `application.ini` for `org.mozilla.*` apps.
2. Beta recipe bundle id corrected `org.mozilla.thunderbird` → `org.mozilla.thunderbirdbeta`.
3. ESR no longer mis-detects as stable (was: ESR install offered stable `151.0.1`).

## Notes
- ESR/beta probe captures the feed's full `…esr`/`…b3` form; it sorts as a
  pre-release (≤ the suffix-less install) so the engine shows "up to date" at the
  current release and never phantoms; a real bump (140.11.1→140.12.0esr) compares newer.
- **beta→beta intra-cycle is invisible**: the install reports a constant `152.0`
  across b1…bN, so only cross-major (153.0bN) is detectable. Accepted limitation.

## Commands
```
swift run --package-path application-test channel-verify "/Applications/Thunderbird.app" --expect stable
swift run --package-path application-test channel-verify "/tmp/tb-daily.dmg" --expect nightly
swift run --package-path application-test channel-verify "/tmp/tb-esr.dmg"   --expect esr
swift run --package-path application-test channel-verify "/tmp/tb-beta.dmg"  --expect beta
```
