# Firefox — channel verification record

Verified 2026-06-04 with `channel-verify` against **real bundles** (all 5 channels
downloaded as official DMGs, mounted read-only, not installed). Firefox was NOT
installed locally — these are the ground-truth identities + post-fix routing.

Authoritative channel marker: `Contents/Resources/application.ini` → `RemotingName`.

| Channel | real bundle id | real short ver | `RemotingName` | detect() | probe → verdict |
|---------|----------------|----------------|----------------|----------|-----------------|
| stable     | `org.mozilla.firefox`                  | `151.0.3` | `firefox`         | stable ✓  | 151.0.3 (not re-run post-fix; unchanged) |
| beta       | `org.mozilla.firefox` (**shared**)     | `152.0`   | `firefox-beta`    | beta ✓    | 152.0b7 (pre-release, up to date) |
| devedition | `org.mozilla.firefoxdeveloperedition`  | `152.0`   | `firefox-dev`     | dev ✓     | 152.0b7 (up to date) |
| esr        | `org.mozilla.firefox` (**shared**)     | `140.11.0`| `firefox-esr`     | esr ✓     | 140.11.0esr (= install, up to date) |
| nightly    | `org.mozilla.nightly`                  | `153.0a1` | `firefox-nightly` | nightly ✓ | 153.0a1 |

## Key facts (vs Thunderbird)
- Firefox **Beta and ESR SHARE `org.mozilla.firefox`** with Stable (TB beta is a
  separate id). App name is plain "Firefox" for all three, version suffix stripped →
  RemotingName is the ONLY signal. Recipe bundle ids were already correct (shared);
  only detection was broken.
- Developer Edition: `RemotingName=firefox-dev`, reports `152.0` (NOT a `b7`), so the
  old "tracks beta train via bN suffix → .beta" assumption was wrong. Recipe channel
  changed `.beta` → `.dev`.

## Fix applied (2026-06-04)
- Same `RemotingName` detection as Thunderbird fixes FF beta (missed updates) and FF
  esr (was cross-channel pushed onto stable `151.0.3`).
- FF devedition recipe channel `.beta` → `.dev`.

## Commands
```
# DMG redirector: https://download.mozilla.org/?product=firefox{,-beta,-devedition,-esr,-nightly}-latest-ssl&os=osx&lang=en-US
swift run --package-path application-test channel-verify "/tmp/ff-esr.dmg"  --expect esr
swift run --package-path application-test channel-verify "/tmp/ff-beta.dmg" --expect beta
swift run --package-path application-test channel-verify "/tmp/ff-dev.dmg"  --expect dev
```
