# Signal — channel verification record

Verified 2026-06-04 with `channel-verify` against the **official zips of both
channels** (extracted, `.app` inspected; not installed). Independent bundle ids
(Pattern A), each with its own electron-builder feed.

| Channel | real bundle id | real short ver | detect() | VendorProbe → verdict |
|---------|----------------|----------------|----------|------------------------|
| stable  | `org.whispersystems.signal-desktop`      | `8.13.0`        | stable ✓ | 8.13.0 = build, up to date |
| beta    | `org.whispersystems.signal-desktop-beta` | `8.14.0-beta.1` | beta ✓   | 8.14.0-beta.1 = build, up to date |

## Notes
- Beta is a separate `Signal Beta.app` with a distinct `-beta` bundle id; detection
  is unambiguous. Both VendorProbe recipes (`latest-mac.yml` / `beta-mac.yml`)
  answered with the build's own version → no phantom update.
- Best-effort one-click on top of electron-updater (universal dmg from the same yml).

## Re-verified 2026-08-09 — both channels, after the beta install-URL fix

Same method, against the **official universal dmgs** of both channels (mounted,
`.app` extracted, not installed).

| Channel | real bundle id | real short ver | detect() | VendorProbe → verdict |
|---------|----------------|----------------|----------|------------------------|
| stable  | `org.whispersystems.signal-desktop`      | `8.22.0`        | stable ✓ | 8.22.0, up to date |
| beta    | `org.whispersystems.signal-desktop-beta` | `8.23.0-beta.1` | beta ✓   | 8.23.0-beta.1, up to date |

Resolved install URLs (each channel's own build, no cross-match):
- stable → `…/signal-desktop-mac-universal-8.22.0.dmg`
- beta   → `…/signal-desktop-beta-mac-universal-8.23.0-beta.1.dmg`

Signature gate inputs, read off both real dmgs:

| | stable | beta |
|---|---|---|
| signed bundle id | `org.whispersystems.signal-desktop` | `org.whispersystems.signal-desktop-beta` |
| Team ID | `U68MSDN6DR` | `U68MSDN6DR` |
| `spctl -a -t install` | accepted, Notarized Developer ID | accepted, Notarized Developer ID |
| `stapler validate` | worked | worked |

**Why neither recipe verifies the feed's sha512:** the yml's `sha512`/`size` cover
the dmg as electron-builder emitted it, before Signal's CI signs and staples it.
The CDN serves the stapled file — `Content-Length` is 2563 bytes larger than the
feed's `size` on *both* channels, and the feed hash matches neither the whole file
nor its leading `size` bytes. A `checksumPattern` built from it would abort every
install at `VendorInstaller` gate 1. (Control: Typeless reads a structurally
identical electron-builder feed with delta 0 — this is Signal's pipeline, not a
property of the format.)

## Commands
```
swift run --package-path application-test channel-verify "/tmp/Signal.app"      --expect stable
swift run --package-path application-test channel-verify "/tmp/Signal Beta.app" --expect beta
```
